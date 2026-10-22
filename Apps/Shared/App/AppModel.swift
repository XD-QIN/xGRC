import BLEKit
import CameraKit
import DesignKit
import Foundation
import Observation
import Persistence
import SessionKit
import SharedState
import SwiftUI
#if os(iOS)
import UIKit
#endif
import UserNotifications
import WidgetKit

/// The app's view of the session, on the watch and on iPhone and iPad.
/// Bridges SessionKit's streams to SwiftUI on the main actor; holds no
/// protocol logic.
@MainActor
@Observable
final class AppModel {
    enum Route: Hashable {
        case addCamera
        case session
        case settings
        case tracks
    }

    enum PairingProgress: Equatable {
        case running(PairingStep)
        case failed(String)
    }

    let coordinator: SessionCoordinator

    var path: [Route] = []
    var cameras: [CameraRecord] = []
    var session = SessionSnapshot()
    var shutter = ShutterSnapshot()
    var geotag = GeotagSnapshot()
    var intervalometer = IntervalometerSnapshot()
    /// The app is on screen with the wrist raised. On iPhone a launch in the
    /// background (Bluetooth or Core Location relaunch, an intent) may report
    /// no scene phase, so `init` starts it from the application state.
    var isSceneActive = true
    var showOnboarding = false
    var bluetooth: CentralState = .unknown
    var settings = AppSettings()
    /// Settings › Language; English until the user picks another.
    private(set) var language = AppLanguage.current
    var discovered: [DiscoveredCamera] = []
    /// Cameras another app already has connected to this device.
    var connectedElsewhere: Set<UUID> = []
    var pairing: PairingProgress?
    var message: String?
    /// Add camera's scan is running; it stops by itself after 30 s.
    private(set) var isScanning = false

    private var scanTask: Task<Void, Never>?
    /// Ends the scan after its budget even when no camera advertises.
    private var scanTimer: Task<Void, Never>?
    /// What the shutter last showed, for haptics and VoiceOver.
    private var lastCue: ShutterCue = .appearance(.idle)
    private var tileState: TileState?
    /// Shutter inputs in the order they happened. One task forwards them, so
    /// a quick tap's touch-up never overtakes its touch-down on the way to
    /// the sequencer (a task per input does not keep that order).
    private let shutterInputs: AsyncStream<ShutterInput>.Continuation
    /// A Double Tap made while the camera link was coming back (the wrist
    /// just raised, the camera waking). It shoots once the link is ready,
    /// if that comes within `heldShotWindow`.
    private var heldShot: Task<Void, Never>?
    static let heldShotWindow: Duration = .seconds(5)

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
        let (inputs, continuation) = AsyncStream.makeStream(of: ShutterInput.self)
        shutterInputs = continuation
        Task {
            for await input in inputs { await coordinator.shutter(input) }
        }
        #if os(iOS)
        isSceneActive = UIApplication.shared.applicationState != .background
        #endif
        Task { [weak self] in
            for await snapshot in coordinator.sessionSnapshots() {
                self?.apply(session: snapshot)
            }
        }
        Task { [weak self] in
            for await snapshot in coordinator.shutterSnapshots() {
                self?.apply(snapshot)
            }
        }
        Task { [weak self] in
            for await state in coordinator.bluetoothStates() {
                self?.bluetooth = state
            }
        }
        Task { [weak self] in
            for await snapshot in coordinator.geotagSnapshots() {
                self?.apply(geotag: snapshot)
            }
        }
        Task { [weak self] in
            for await snapshot in coordinator.intervalometerSnapshots() {
                self?.applyIntervalometer(snapshot)
            }
        }
    }

    var mode: SessionMode { settings.sessionMode }

    func setMode(_ mode: SessionMode) {
        settings.sessionMode = mode
        Task {
            do {
                try await coordinator.setMode(mode)
            } catch {
                message = Self.describe(error, driverID: session.camera?.driverID)
            }
            await reload()
            // The mode decides the Island's shutter and the tile's Shoot.
            refreshActivity()
        }
    }

    // MARK: Scene

    /// Wrist down keeps the app frontmost but inactive: countdowns, bulb and
    /// timelapses keep running. Only leaving the app (background) releases
    /// every button (architecture doc § Gesture timing: Return to Clock).
    func scenePhaseChanged(_ phase: ScenePhase) {
        isSceneActive = phase == .active
        switch phase {
        case .background:
            send(.sceneInactive)
        case .active:
            Task { await coordinator.sceneBecameActive() }
            // A Live Activity can only be requested from the foreground.
            refreshActivity()
        default:
            break
        }
    }

    /// Loads the stores and, with Auto reconnect on, re-opens the session
    /// that was running when the app last stopped (with Auto reconnect off
    /// the coordinator drops it). The first launch goes straight to *Add camera*.
    func launch() async {
        await reload()
        if !settings.onboardingDone { showOnboarding = true }
        if let id = settings.lastActiveCameraID {
            let resumes = settings.autoReconnect && cameras.contains { $0.id == id }
            if resumes { path = [.session] }
            Task { await coordinator.restoreSession() }
            if resumes { return }
        }
        if cameras.isEmpty, path.isEmpty { path = [.addCamera] }
    }

    func reload() async {
        cameras = await coordinator.cameras()
        settings = await coordinator.stores.settings.load()
        updateTile()
        updateIdleTimer()
    }

    private func apply(session snapshot: SessionSnapshot) {
        let wasEnded = session.ended != nil
        // An error belongs to the camera and the link it came from.
        if snapshot.camera?.id != session.camera?.id
            || (snapshot.link == .ready && session.link != .ready) {
            message = nil
        }
        session = snapshot
        if heldShot != nil, !isLinkReturning {
            heldShot?.cancel()
            heldShot = nil
            // Back in time: the held shot goes out. Busy, failed or ended: dropped.
            if isReady { shutterInputs.yield(.shoot) }
        }
        updateTile()
        updateIdleTimer()
        refreshActivity()
        if let text = endedText, !wasEnded {
            // Auto disconnect: back to the camera list, which says why.
            path.removeAll { $0 == .session }
            notifyIfAway(String(localized: "Camera disconnected"), text)
        }
    }

    /// Why the last session ended by itself, shown on the camera list.
    var endedText: String? {
        switch session.ended {
        case .idle(let minutes)?:
            String(localized: "Disconnected after \(minutes) minutes without use.")
        case .unreachable(let minutes)?:
            String(localized: "Disconnected after \(minutes) minutes without reaching the camera.")
        case .linkLost?:
            String(localized: "The camera disconnected. Auto reconnect is off in Settings.")
        case nil:
            nil
        }
    }

    private func apply(geotag snapshot: GeotagSnapshot) {
        let wasFailed: Bool
        if case .failed = geotag.status { wasFailed = true } else { wasFailed = false }
        geotag = snapshot
        updateTile()
        if case .failed = snapshot.status, !wasFailed, let message = geotagMessage {
            refreshActivity(.geotagFailed(message.text))
        } else {
            refreshActivity()
        }
    }

    /// Writes the state the watch's Smart Stack tile and the iPhone's
    /// controls show into the App Group, and reloads them only when they would
    /// look different (the reload budget is small).
    private func updateTile() {
        #if os(iOS)
        // The iPhone's Shoot control runs with the app in the background.
        let shootsInBackground = backgroundShooting
        #else
        let shootsInBackground = true
        #endif
        let state = TileState(session: session, geotag: geotag, mode: mode, backgroundShooting: shootsInBackground)
        if let tileState, !state.differsVisibly(from: tileState) { return }
        tileState = state
        guard let directory = AppGroup.directory else { return }
        try? state.save(to: directory)
        #if os(watchOS)
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.tileKind)
        #elseif os(iOS)
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: AppGroup.shootControlKind)
        }
        #endif
    }

    /// iPhone and iPad: the screen stays on while a session that uses the
    /// remote is open, so auto-lock does not cancel a release delay, close a
    /// bulb or stall a timelapse (product spec: keep screen on). Leaving the
    /// app still releases everything.
    private func updateIdleTimer() {
        #if os(iOS)
        let keepOn = mode.usesRemote && session.camera != nil && session.link != .ended && session.ended == nil
        if UIApplication.shared.isIdleTimerDisabled != keepOn {
            UIApplication.shared.isIdleTimerDisabled = keepOn
        }
        #endif
    }

    // MARK: Live Activity

    #if os(iOS)
    let liveActivity = LiveActivityController()
    #endif

    /// The session's brand can shoot while the app is in the background.
    private var backgroundShooting: Bool {
        session.camera
            .flatMap { coordinator.registry.driverType(id: $0.driverID) }?
            .descriptor.capabilities.contains(.backgroundShooting) ?? false
    }

    /// Sends the session to the Live Activity on iPhone; a no-op on the watch.
    private func refreshActivity(_ event: ActivityEvent? = nil) {
        #if os(iOS)
        let state = ActivityState(session: session, geotag: geotag, shutter: shutter,
                                  timelapseRunning: intervalometer.isRunning, mode: mode,
                                  backgroundShooting: backgroundShooting)
        liveActivity.idleStaleAfter = ActivityPlanner.idleStaleAfter(autoDisconnectMinutes: settings.autoDisconnectMinutes)
        liveActivity.update(state, event: event, enabled: settings.liveActivity, appActive: isSceneActive)
        #endif
    }

    #if os(iOS)
    /// The Island's shutter or the Shoot control failed before any shot.
    func reportIntentFailure(_ error: Error) {
        refreshActivity(.shotFinished(.failed(.notConnected), delayed: false))
    }
    #endif

    // MARK: Scan and pair

    /// Foreground scan, stopped after 30 s or on leaving Add camera (architecture doc § Budgets).
    func startScan() {
        stopScan()
        isScanning = true
        discovered = []
        Task { connectedElsewhere = await coordinator.peripheralsConnectedElsewhere() }
        scanTask = Task { [weak self] in
            guard let self else { return }
            let stream = await coordinator.scan()
            for await found in stream {
                if Task.isCancelled { break }
                if let index = discovered.firstIndex(where: { $0.id == found.id }) {
                    // A camera keeps its row: RSSI changes with every advertisement.
                    discovered[index] = found
                } else {
                    // Placed by its signal when first seen, then left there.
                    let index = discovered.firstIndex { $0.advertisement.rssi < found.advertisement.rssi }
                    discovered.insert(found, at: index ?? discovered.endIndex)
                }
            }
        }
        // The deadline is its own timer: with nothing advertising, the
        // stream yields nothing to check a deadline against.
        scanTimer = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(30))) != nil else { return }
            self?.scanTask?.cancel()
            self?.scanTask = nil
            self?.isScanning = false
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        scanTimer?.cancel()
        scanTimer = nil
        isScanning = false
    }

    func pair(_ camera: DiscoveredCamera) async {
        stopScan()
        #if os(iOS)
        liveActivity.resume()
        #endif
        pairing = .running(.connecting)
        do {
            _ = try await coordinator.pair(camera) { step in
                Task { @MainActor [weak self] in self?.pairing = .running(step) }
            }
            pairing = nil
            await reload()
            // Paired: the session is installed, even if the sheet went away meanwhile.
            path = [.session]
            requestNotificationPermission()
        } catch {
            // Cancelled from the pairing sheet: no failure to show.
            if Task.isCancelled || error is CancellationError {
                pairing = nil
            } else {
                pairing = .failed(Self.describe(error, driverID: camera.match.driverID))
            }
        }
    }

    /// *Cancel* on the pairing sheet: stops a pairing that still runs and
    /// stays on Add camera, scanning again. A session a pairing already
    /// installed is left alone.
    func cancelPairing() {
        let running: Bool
        if case .running = pairing { running = true } else { running = false }
        pairing = nil
        Task {
            if running { await coordinator.endSession() }
            await reload()
            if path.last == .addCamera { startScan() }
        }
    }

    /// Pairs the camera the system accessory picker returned, once a scan
    /// sees it (iOS 18+, behind the `XGRC_ACCESSORY_SETUP` flag).
    func pairPicked(peripheralID: UUID) {
        startScan()
        Task {
            for _ in 0..<40 {
                if let camera = discovered.first(where: { $0.id == peripheralID }) {
                    await pair(camera)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            pairing = .failed(String(localized: "The camera was not found. Check that it is in pairing mode."))
        }
    }

    // MARK: Session

    func open(_ record: CameraRecord) {
        path = [.session]
        #if os(iOS)
        liveActivity.resume()
        #endif
        requestNotificationPermission()
        Task {
            do {
                try await coordinator.activate(record)
            } catch is CancellationError {
                // Ended (by the user or auto disconnect) before the camera answered.
            } catch {
                message = Self.describe(error, driverID: session.camera?.driverID)
            }
        }
    }

    /// Opens the running session's screen, if there is one.
    func showActiveSession() {
        guard session.camera != nil, session.link != .ended else { return }
        path = [.session]
    }

    func endSession() async {
        // The Live Activity goes at once, not after the camera is released.
        #if os(iOS)
        liveActivity.endNow()
        #endif
        // Back to the list at once: the teardown can wait on writes to a
        // camera that is gone (the coordinator guards a second end).
        path = []
        await coordinator.endSession()
    }

    func forget(_ record: CameraRecord) async {
        do {
            try await coordinator.forget(record)
        } catch {
            message = Self.describe(error, driverID: session.camera?.driverID)
        }
        await reload()
        path = []
    }

    func send(_ input: ShutterInput) {
        if input == .shoot, isLinkReturning {
            holdShot()
            return
        }
        shutterInputs.yield(input)
    }

    /// Keeps a shot made while the link comes back, for `heldShotWindow`.
    private func holdShot() {
        heldShot?.cancel()
        message = String(localized: "Reconnecting. The photo is taken when the camera is back.")
        heldShot = Task { [weak self] in
            try? await Task.sleep(for: Self.heldShotWindow)
            guard !Task.isCancelled, let self else { return }
            self.heldShot = nil
            self.message = String(localized: "The camera did not come back in time. No photo was taken.")
            TallyHaptic.notConfirmed.play()
        }
    }

    func retry() {
        #if os(iOS)
        liveActivity.resume()
        #endif
        Task {
            do {
                try await coordinator.retry()
            } catch {
                message = Self.describe(error, driverID: session.camera?.driverID)
            }
        }
    }

    func finishOnboarding() {
        showOnboarding = false
        updateSettings { $0.onboardingDone = true }
        requestNotificationPermission()
        // The scan under the onboarding sheet may have run out unseen.
        if path.last == .addCamera { startScan() }
    }

    // MARK: Intervalometer

    func startIntervalometer(_ plan: IntervalometerPlan) {
        Task {
            do {
                try await coordinator.startIntervalometer(plan)
            } catch {
                message = Self.describe(error, driverID: session.camera?.driverID)
            }
        }
    }

    func stopIntervalometer() {
        Task { await coordinator.stopIntervalometer() }
    }

    private func applyIntervalometer(_ snapshot: IntervalometerSnapshot) {
        let wasRunning = intervalometer.isRunning
        intervalometer = snapshot
        if wasRunning != snapshot.isRunning { refreshActivity() }
        guard wasRunning, case .finished(let end) = snapshot.state else { return }
        switch end {
        case .failures:
            TallyHaptic.notConfirmed.play()
            notifyIfAway(String(localized: "Timelapse stopped"), String(localized: "Three frames failed in a row."))
        case .completed:
            TallyHaptic.fired.play()
            notifyIfAway(String(localized: "Timelapse done"), String(localized: "\(snapshot.confirmed) of \(snapshot.frame) frames confirmed."))
        case .stopped:
            break
        }
    }

    // MARK: Notices

    /// The banner for the active session, if any (product spec § States & errors).
    var noticeText: String? {
        if session.notices.contains(.backgroundBudget(exceeded: true)) {
            return String(localized: "The watch will keep the camera connected only while xGRC is on screen until you use the app again.")
        }
        if session.notices.contains(.reducedRange) {
            #if os(iOS)
            return String(localized: "Bring \(BrandText.thisDevice) closer to the camera. If it keeps failing, turn Bluetooth off and on in Control Center.")
            #else
            return String(localized: "Bring \(BrandText.thisDevice) closer to the camera. If it keeps failing, turn Bluetooth off and on in Control Centre.")
            #endif
        }
        return nil
    }

    /// Asks for notification permission while the app is on screen, so the
    /// prompt never comes from a result that lands with the app in the
    /// background, where the system would not show it. Once answered, the
    /// system returns the answer without asking again.
    private func requestNotificationPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    /// Wrist-down fallback: haptics are dropped while the app is inactive, so
    /// a result that lands then is also posted as a local notification.
    private func notifyIfAway(_ title: String, _ body: String) {
        guard !isSceneActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    // MARK: Geotag

    func startGeotag() {
        Task { _ = await coordinator.startGeotag() }
    }

    func stopGeotag() {
        Task { await coordinator.stopGeotag() }
    }

    /// The active camera's saved record, which carries per-camera options.
    var activeRecord: CameraRecord? {
        guard let id = session.camera?.id else { return nil }
        return cameras.first { $0.id == id }
    }

    func setKeepAwake(_ keepAwake: Bool) {
        guard let record = activeRecord else { return }
        Task {
            do {
                try await coordinator.setKeepAwake(keepAwake, for: record)
            } catch {
                message = Self.describe(error, driverID: session.camera?.driverID)
            }
            await reload()
        }
    }

    struct GeotagMessage: Equatable {
        let text: String
        let isFault: Bool
    }

    /// The line for a geotag failure, on the Geotag page and from Siri.
    func geotagFailureText(_ failure: GeotagFailure) -> String {
        switch failure {
        case .locationDenied:
            String(localized: "xGRC needs Location. Allow it in Settings › Privacy › Location Services.")
        case .preciseLocationOff:
            String(localized: "Turn on Precise Location for xGRC in Settings › Privacy › Location Services. Approximate fixes are too coarse to tag photos.")
        case .cameraSettingOff:
            BrandText.locationOff(driverID: session.camera?.driverID) + String(localized: ", then start again.")
        case .busy:
            String(localized: "Another phone, watch or app is sending this camera its location. Stop it there.")
        case .unsupported:
            String(localized: "This camera can't take locations over Bluetooth.")
        case .other(let reason):
            reason.localizedFromCatalog
        }
    }

    /// One line on the Geotag page when something needs the user.
    var geotagMessage: GeotagMessage? {
        switch geotag.status {
        case .failed(let failure):
            return GeotagMessage(text: geotagFailureText(failure), isFault: true)
        case .noFix:
            return GeotagMessage(text: String(localized: "No GPS fix — photos untagged"), isFault: false)
        case .cameraNotTagging:
            return GeotagMessage(text: String(localized: "The camera is not taking locations — photos untagged. ")
                                     + BrandText.locationOff(driverID: session.camera?.driverID)
                                     + String(localized: ", or stop location on any other phone or watch."),
                                 isFault: true)
        case .paused:
            return GeotagMessage(text: String(localized: "Camera disconnected. Location resumes when it's back."), isFault: false)
        case .waitingForFix:
            return GeotagMessage(text: String(localized: "Waiting for GPS…"), isFault: false)
        case .waitingForCamera:
            return GeotagMessage(text: BrandText.waitingForCamera, isFault: false)
        default:
            if geotag.cameraLocationEnabled == false {
                return GeotagMessage(text: BrandText.locationOff(driverID: session.camera?.driverID), isFault: true)
            }
            return nil
        }
    }

    // MARK: Settings

    func setLanguage(_ language: AppLanguage) {
        AppLanguage.select(language)
        self.language = language
        // The Live Activity and the tile redraw in the new language.
        tileState = nil
        updateTile()
        refreshActivity()
    }

    func updateSettings(_ change: @escaping @Sendable (inout AppSettings) -> Void) {
        Task {
            do {
                settings = try await coordinator.stores.settings.update(change)
                await coordinator.settingsChanged()
            } catch {
                message = Self.describe(error, driverID: session.camera?.driverID)
            }
            // Live Activity on or off, the auto-disconnect time, the mode.
            updateTile()
            updateIdleTimer()
            refreshActivity()
        }
    }

    // MARK: Presentation

    var appearance: ShutterAppearance { Self.appearance(for: shutter.phase) }

    var linkIndicator: LinkIndicator {
        switch session.link {
        case .ready?: .connected
        case .connecting?, .bonding?, .registering?, .reconnecting?: .connecting
        case .outOfRange?: .off
        case .busy?: .busy
        case .pairAgain?, .failed?, .firmwareChanged?: .pairAgain
        case .ended?, nil: .saved
        }
    }

    var isReady: Bool { session.link == .ready }

    /// The link is coming back by itself, so a Double Tap waits for it
    /// instead of falling through to the system's scroll.
    var isLinkReturning: Bool {
        switch session.link {
        case .connecting?, .registering?, .reconnecting?: true
        default: false
        }
    }

    /// The connected camera's driver capabilities: half-press, bulb, acks.
    var capabilities: DriverCapabilities {
        session.camera.flatMap { coordinator.registry.driverType(id: $0.driverID) }?.descriptor.capabilities ?? []
    }

    /// The camera can hold the shutter open (bulb, or Time on Nikon).
    var hasBulb: Bool { !capabilities.isDisjoint(with: [.bulb, .bulbAsTime]) }

    /// A bulb time is set and the camera has bulb: one tap opens the bulb,
    /// it counts down and closes by itself.
    var bulbMode: Bool { hasBulb && settings.bulbSeconds > 0 }

    /// Settings › Tap to shoot (watch only): one tap focuses, then shoots.
    var tapToShoot: Bool {
        #if os(watchOS)
        settings.tapToShoot
        #else
        false
        #endif
    }

    /// The gesture line under the shutter when nothing else needs saying.
    var gestureHint: String {
        if bulbMode { return String(localized: "tap = bulb \(SettingText.bulb(settings.bulbSeconds))") }
        if tapToShoot { return String(localized: "tap = shoot") }
        return capabilities.contains(.halfPress) ? String(localized: "tap = focus · 2× = shoot")
            : String(localized: "2× = shoot")
    }

    /// A standing note for brands with a camera-side catch (Canon Remote,
    /// Nikon), or a bulb time the camera cannot use.
    var shutterNote: String? {
        if settings.bulbSeconds > 0, session.camera != nil, !hasBulb {
            return String(localized: "This camera has no bulb, so the bulb time is not used.")
        }
        if bulbMode, settings.bulbSeconds > 60 * 60, session.camera?.driverID == FujifilmDriver.descriptor.id {
            return String(localized: "Fujifilm cameras end a bulb by themselves at 60 minutes.")
        }
        return BrandText.shutterNote(driverID: session.camera?.driverID)
    }

    /// One line under the camera name when the link is not ready.
    var linkMessage: String? {
        switch session.link {
        case .connecting?: String(localized: "Looking for \(session.camera?.name ?? String(localized: "the camera"))…")
        case .bonding?: BrandText.bonding(driverID: session.camera?.driverID ?? "")
        case .registering?: String(localized: "Registering…")
        case .reconnecting?: String(localized: "Looking for \(session.camera?.name ?? String(localized: "the camera"))…")
        case .outOfRange?: String(localized: "Camera off or out of range")
        case .busy?: String(localized: "Linked to another phone, watch or app. Disconnect it there.")
        case .pairAgain?: String(localized: "The camera no longer recognises \(BrandText.thisDevice). Pair again.")
        case .firmwareChanged?: String(localized: "The camera's firmware changed. Forget and pair again.")
        case .failed(let reason)?: reason.localizedFromCatalog
        default: nil
        }
    }

    /// What the shutter shows, for haptics and VoiceOver: a countdown and an
    /// open bulb are their own states, not *Focusing*.
    private enum ShutterCue: Equatable {
        case countdown
        case bulb
        case appearance(ShutterAppearance)
    }

    private static func cue(for phase: ShutterPhase) -> ShutterCue {
        switch phase {
        case .countdown: .countdown
        case .bulbOpen: .bulb
        default: .appearance(appearance(for: phase))
        }
    }

    static func appearance(for phase: ShutterPhase) -> ShutterAppearance {
        switch phase {
        case .idle: .idle
        case .focusing, .shooting, .bulbOpen, .countdown: .focusing
        case .focused: .focused
        case .result(.acknowledged): .fired
        case .result(.assumed): .sent
        case .result(.unconfirmed), .result(.failed): .notConfirmed
        case .result(.cancelled): .idle
        }
    }

    private func apply(_ snapshot: ShutterSnapshot) {
        let wasResult: Bool
        if case .result = shutter.phase { wasResult = true } else { wasResult = false }
        shutter = snapshot
        if case .result(let result) = snapshot.phase, !wasResult {
            refreshActivity(.shotFinished(result, delayed: snapshot.lastShotDelayed))
        } else {
            refreshActivity()
        }
        let cue = Self.cue(for: snapshot.phase)
        if cue != lastCue {
            lastCue = cue
            // A timelapse frame is not a gesture: no haptic or announcement per
            // frame; the run's end has its own.
            if !intervalometer.isRunning { play(cue, snapshot) }
        }
        switch snapshot.phase {
        case .result(.failed(let error)): message = Self.describe(error, driverID: session.camera?.driverID)
        case .result(.unconfirmed(.shutterTimedOut)):
            message = String(localized: "The camera did not respond; is it in playback or a menu?")
        case .focusing, .shooting, .countdown: message = nil
        default: break
        }
    }

    private func play(_ cue: ShutterCue, _ snapshot: ShutterSnapshot) {
        switch cue {
        case .countdown:
            AccessibilityNotification.Announcement(String(localized: "Release delay started")).post()
        case .bulb:
            AccessibilityNotification.Announcement(String(localized: "Bulb open")).post()
        case .appearance(let appearance):
            if snapshot.lastShotDelayed, case .result = snapshot.phase {
                // Release delay: one haptic on release, or a notification with the wrist down.
                TallyHaptic.delayRelease.play()
                if let result = snapshot.lastResult {
                    notifyIfAway(String(localized: "Release delay"), result.isConfirmed ? String(localized: "Fired, confirmed") : String(localized: "Sent, not confirmed"))
                }
            } else {
                appearance.haptic?.play()
            }
            if let announcement = appearance.announcement {
                AccessibilityNotification.Announcement(String(localized: announcement.inAppLanguage)).post()
            }
        }
    }

    /// Copy for an error; `driverID` picks the brand's wording where it differs.
    static func describe(_ error: Error, driverID: String? = nil) -> String {
        switch error {
        case ShotError.remoteControlOff, CameraError.remoteControlOff:
            String(localized: "Turn on Bluetooth Rmt Ctrl on the camera")
        case ShotError.busy, CameraError.busy:
            String(localized: "Linked to another phone, watch or app")
        case CameraError.pairAgain:
            String(localized: "The camera no longer recognises \(BrandText.thisDevice). Pair again.")
        case CameraError.pairingRejected:
            String(localized: "The camera declined or did not answer. Start pairing on the camera again.")
        case CameraError.unsupported:
            String(localized: "This camera or its current Bluetooth setting is not supported")
        case CameraError.missingCharacteristic:
            String(localized: "The camera's firmware changed. Forget and pair again.")
        case CameraError.locationLinkOff:
            BrandText.locationOff(driverID: driverID)
        case SessionError.notInMode(let mode):
            mode == .geotagOnly ? String(localized: "The mode is Geotag only. Change it in Settings.") : String(localized: "Not available in this mode")
        case SessionError.bluetooth(let state), GATTError.bluetoothUnavailable(let state):
            state == .unauthorized ? String(localized: "xGRC needs Bluetooth. Allow it in Settings.") : String(localized: "Bluetooth is off")
        case SessionError.noActiveSession, ShotError.notConnected:
            String(localized: "No camera is connected")
        case SessionError.notReady:
            String(localized: "The camera is not connected yet")
        case SessionError.unknownDriver:
            String(localized: "This version of xGRC does not support this camera")
        case SessionError.bulbNeedsApp:
            String(localized: "Bulb time is set. Open xGRC to take a bulb shot.")
        case GATTError.timeout, CameraError.transport(.timeout), ShotError.transport(.timeout):
            String(localized: "The camera did not answer in time")
        case ShotError.transport(.disconnected), CameraError.transport(.disconnected), GATTError.disconnected:
            String(localized: "The camera disconnected")
        case GATTError.insufficientAuthentication, GATTError.peerRemovedPairing,
             CameraError.transport(.insufficientAuthentication), CameraError.transport(.peerRemovedPairing):
            String(localized: "The camera no longer recognises \(BrandText.thisDevice). Pair again.")
        case GATTError.characteristicNotFound, CameraError.transport(.characteristicNotFound):
            String(localized: "The camera's firmware changed. Forget and pair again.")
        case GATTError.att, CameraError.transport(.att), ShotError.transport(.att):
            String(localized: "The camera refused the command. Check that it is not in playback or a menu.")
        default:
            // Not a raw Swift error description on screen.
            String(localized: "Something went wrong talking to the camera. Try again.")
        }
    }
}
