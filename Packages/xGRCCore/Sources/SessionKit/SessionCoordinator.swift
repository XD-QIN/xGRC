import BLEKit
import CameraKit
import Foundation
import LocationKit
import Persistence

/// A camera found by a foreground scan.
public struct DiscoveredCamera: Identifiable, Hashable, Sendable {
    public var id: UUID { advertisement.peripheralID }
    public let advertisement: Advertisement
    public let match: CameraMatch
    public let isDemo: Bool
}

/// What the app shows about the session.
public struct SessionSnapshot: Hashable, Sendable {
    public var camera: CameraRecord?
    public var link: LinkState?
    public var notices: Set<SessionNotice>
    /// Set when the last session ended by itself (auto disconnect); cleared
    /// when the next one starts.
    public var ended: SessionEndReason?

    public init(camera: CameraRecord? = nil, link: LinkState? = nil, notices: Set<SessionNotice> = [],
                ended: SessionEndReason? = nil) {
        self.camera = camera
        self.link = link
        self.notices = notices
        self.ended = ended
    }
}

public enum SessionError: Error, Hashable, Sendable {
    case unknownDriver(String)
    case bluetooth(CentralState)
    case noActiveSession
    /// The action is not part of the current mode (e.g. shooting in Geotag only).
    case notInMode(SessionMode)
    /// The camera is not connected right now.
    case notReady
    /// *Shoot* from an intent with a bulb time set, on a camera whose bulb
    /// toggles (Sony, Nikon Time), while nothing keeps the app running to
    /// close it: a lone press would open a bulb nobody closes.
    case bulbNeedsApp
}

/// What *Shoot* from an intent reports.
public enum IntentShot: Hashable, Sendable {
    case result(ShotResult)
    /// The release delay started; the shot fires when it ends.
    case countdown(seconds: Int)
    /// Bulb mode: a timed bulb started (after the release delay, if one is set).
    case bulb(seconds: Int, delay: Int)
    /// The shot closed a bulb that was open.
    case bulbClosed
    /// The shot cancelled a running release-delay countdown.
    case countdownCancelled
    /// The camera had not answered when the intent had to return.
    case stillRunning
}

/// The task's value, or `nil` after `timeout`. Unlike `withTimeout`, the
/// task keeps running and the caller does not wait for it.
func value<T: Sendable>(of task: Task<T, Never>, within timeout: Duration) async -> T? {
    let once = ResumeOnce<T?>()
    return await withCheckedContinuation { continuation in
        once.set(continuation)
        Task { once.resume(with: await task.value) }
        Task {
            try? await Task.sleep(for: timeout)
            once.resume(with: nil)
        }
    }
}

/// Resumes a continuation with the first value it is given. `set` runs
/// before either racer starts.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    func set(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with value: T) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

/// Holds at most one `CameraSession` (fixed decision 1: one camera at a time).
/// Switching cameras is `end(current)` then `connect(next)`, never two links at once.
public actor SessionCoordinator {
    public nonisolated let registry: DriverRegistry
    public nonisolated let stores: Stores
    public nonisolated let logger: TranscriptLogger

    private let central: any BluetoothCentral
    private let demoCentral: DemoCentral
    private let location: any LocationSource
    private let demoLocation: any LocationSource
    private let identities: IdentityStore
    private var session: CameraSession?
    private var forwarders: [Task<Void, Never>] = []
    /// The connect of `activate`, owned here so `endSession` can cancel a
    /// camera that is off or out of range.
    private var activation: Task<Void, Error>?
    private var activating: CameraRecord?
    /// The ended session's teardown, which can wait on writes to a camera
    /// that is gone. The next session connects only after it, so the old
    /// teardown never cancels the new link (or its location updates).
    private var teardown: Task<Void, Never>?
    /// Bumped by every activate, pair and end: a connect that finishes
    /// under an older generation installs nothing.
    private var generation = 0
    private var autoDisconnectTask: Task<Void, Never>?
    /// Geotagging should run whenever the link is ready: Geotag only mode,
    /// or the user started it and has not stopped it.
    private var wantsGeotag = false
    /// Settings › Auto reconnect, read at install and on every settings change.
    private var autoReconnect = true

    private let sessionUpdates = Broadcaster<SessionSnapshot>(replayLast: true)
    private let shutterUpdates = Broadcaster<ShutterSnapshot>(replayLast: true)
    private let geotagUpdates = Broadcaster<GeotagSnapshot>(replayLast: true)
    private let intervalometerUpdates = Broadcaster<IntervalometerSnapshot>(replayLast: true)
    private let rescanOnDisconnect: Bool
    private var current = SessionSnapshot()
    private var autoDisconnect: AutoDisconnect?
    /// One auto-disconnect minute; shorter in tests.
    private let autoDisconnectUnit: Duration
    private let autoDisconnectCheck: Duration

    /// - Parameters:
    ///   - location: Core Location on a device; the demo camera always uses `demoLocation`.
    public init(registry: DriverRegistry = .standard, stores: Stores, central: any BluetoothCentral,
                demoCentral: DemoCentral = DemoCentral(),
                location: any LocationSource = SimulatedLocationSource(),
                demoLocation: any LocationSource = SimulatedLocationSource(),
                rescanOnDisconnect: Bool = false,
                autoDisconnectUnit: Duration = .seconds(60),
                autoDisconnectCheck: Duration = .seconds(15),
                logger: TranscriptLogger) {
        self.registry = registry
        self.stores = stores
        self.central = central
        self.demoCentral = demoCentral
        self.location = location
        self.demoLocation = demoLocation
        self.rescanOnDisconnect = rescanOnDisconnect
        self.autoDisconnectUnit = autoDisconnectUnit
        self.autoDisconnectCheck = autoDisconnectCheck
        self.logger = logger
        self.identities = IdentityStore(secrets: stores.secrets)
        sessionUpdates.yield(SessionSnapshot())
        shutterUpdates.yield(ShutterSnapshot())
        geotagUpdates.yield(GeotagSnapshot())
        intervalometerUpdates.yield(IntervalometerSnapshot())
    }

    public nonisolated func sessionSnapshots() -> AsyncStream<SessionSnapshot> { sessionUpdates.stream() }
    public nonisolated func shutterSnapshots() -> AsyncStream<ShutterSnapshot> { shutterUpdates.stream() }
    public nonisolated func geotagSnapshots() -> AsyncStream<GeotagSnapshot> { geotagUpdates.stream() }
    public nonisolated func intervalometerSnapshots() -> AsyncStream<IntervalometerSnapshot> {
        intervalometerUpdates.stream()
    }
    public nonisolated func bluetoothStates() -> AsyncStream<CentralState> { central.stateUpdates() }

    public func cameras() async -> [CameraRecord] {
        await stores.cameras.load()
    }

    // MARK: Scanning and pairing

    /// Foreground scan, classified by the driver registry. Includes the demo
    /// camera when *Demo camera* is on.
    public func scan() async -> AsyncStream<DiscoveredCamera> {
        let showDemo = await stores.settings.load().showDemoCamera
        let registry = self.registry
        let real = central.scan()
        let demo = showDemo ? demoCentral.scan() : nil
        let logger = self.logger
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await advertisement in real {
                            guard let match = registry.match(advertisement) else { continue }
                            await logger.log(TranscriptEntry(
                                t: await logger.elapsed(), op: .scan,
                                bytes: advertisement.manufacturerData?.hexString,
                                note: "\(match.displayName) rssi \(advertisement.rssi) \(match.details)"))
                            continuation.yield(DiscoveredCamera(advertisement: advertisement, match: match, isDemo: false))
                        }
                    }
                    if let demo {
                        group.addTask {
                            for await advertisement in demo {
                                guard let match = registry.match(advertisement) else { continue }
                                continuation.yield(DiscoveredCamera(advertisement: advertisement, match: match, isDemo: true))
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Peripherals another app (usually the maker's) already has connected to
    /// this device. Add camera warns that the maker's app may hold the
    /// camera's lock (product spec § States & errors).
    public func peripheralsConnectedElsewhere() async -> Set<UUID> {
        let services = registry.drivers.flatMap { $0.serviceUUIDs }
        guard !services.isEmpty else { return [] }
        let ownID = session?.record.peripheralID
        return Set(await central.connectedPeripherals(withServices: services)).subtracting([ownID].compactMap { $0 })
    }

    /// Pairs with a scanned camera, saves it, and makes it the active camera.
    public func pair(_ camera: DiscoveredCamera,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraRecord {
        await endSession()
        await teardown?.value
        generation += 1
        let pairing = generation
        let central = camera.isDemo ? demoCentral : self.central
        guard registry.driverType(id: camera.match.driverID) != nil else {
            throw SessionError.unknownDriver(camera.match.driverID)
        }
        let state = await central.currentState()
        guard state == .poweredOn else { throw SessionError.bluetooth(state) }

        progress(.connecting)
        await logger.update(camera: camera.match.displayName, maxWriteWithoutResponse: nil)
        await logger.log(.connect, note: "pairing \(camera.match.displayName) \(camera.match.details)")
        let raw = try await central.connect(camera.advertisement.peripheralID, autoReconnect: false,
                                            timeout: .seconds(30))
        let transport = RecordingTransport(raw, logger: logger)
        let linkEvents = transport.linkEvents()
        let record: CameraRecord
        let driver: any CameraDriver
        let client: ClientIdentity
        let identity: CameraIdentity
        let mode: SessionMode
        do {
            guard let made = registry.makeDriver(id: camera.match.driverID, transport: transport) else {
                throw SessionError.unknownDriver(camera.match.driverID)
            }
            driver = made
            await logger.update(camera: nil,
                                maxWriteWithoutResponse: await transport.maximumWriteLength(withResponse: false))
            mode = await stores.settings.load().sessionMode
            await driver.setFeatures(remote: mode.usesRemote, geotag: mode.usesGeotag)
            client = try identities.clientIdentity()
            identity = try await driver.pair(camera.advertisement, client: client, progress: progress)

            record = CameraRecord(driverID: camera.match.driverID, name: camera.match.displayName,
                                  modelCode: camera.match.modelCode,
                                  peripheralID: camera.advertisement.peripheralID,
                                  isDemo: camera.isDemo, lastConnectedAt: Date())
            try identities.setCameraIdentity(identity, for: record.id)
            try await stores.cameras.update { records in
                records.removeAll { $0.peripheralID == record.peripheralID }
                records.append(record)
            }
        } catch {
            // Nothing holds the link yet: drop it, so the camera is free.
            await central.cancelConnection(camera.advertisement.peripheralID)
            throw error
        }
        let session = CameraSession(record: record, central: central, transport: transport, driver: driver,
                                    identity: identity, client: client, logger: logger,
                                    configuration: await sequencerConfiguration(),
                                    rescanOnDisconnect: rescanOnDisconnect, linkEvents: linkEvents)
        guard await install(session, generation: pairing, mode: mode) else { throw CancellationError() }
        await session.startRegistered()
        if mode == .geotagOnly { await startGeotag() }
        return record
    }

    // MARK: Sessions

    /// Connects to a saved camera and makes it the active one. The connect is
    /// a pending connect with auto-reconnect: it completes when the camera is
    /// on and in range.
    ///
    /// The connect belongs to the coordinator: `endSession()` (or the
    /// next `activate`) cancels it, and the unreachable auto-disconnect
    /// timer runs from the start, so a camera that is off never keeps the
    /// app waiting. A cancelled activation throws `CancellationError`.
    public func activate(_ record: CameraRecord) async throws {
        if let session, session.record.id == record.id { return }
        if let activation, activating?.id == record.id { return try await activation.value }
        await endSession()
        await teardown?.value
        guard registry.driverType(id: record.driverID) != nil else {
            throw SessionError.unknownDriver(record.driverID)
        }
        generation += 1
        let attempt = generation
        activating = record
        current = SessionSnapshot(camera: record, link: .connecting)
        sessionUpdates.yield(current)
        await startAutoDisconnect(for: record.id)
        let task = Task { try await self.connect(record, generation: attempt) }
        activation = task
        defer {
            if generation == attempt {
                activation = nil
                activating = nil
            }
        }
        do {
            try await task.value
        } catch {
            if generation == attempt, !(error is CancellationError) {
                // Nothing will connect: say why instead of *Connecting* for
                // good, and stop the auto disconnect that has nothing to end.
                await logger.log(.error, note: "connect failed: \(error)")
                autoDisconnectTask?.cancel()
                autoDisconnectTask = nil
                autoDisconnect = nil
                current = SessionSnapshot(camera: record, link: .failed(describeFailure(error)))
                sessionUpdates.yield(current)
            }
            throw error
        }
    }

    private func connect(_ record: CameraRecord, generation attempt: Int) async throws {
        let central = record.isDemo ? demoCentral : self.central
        await logger.update(camera: record.name, maxWriteWithoutResponse: nil)
        await logger.log(.connect, note: "connecting \(record.name)")

        let raw = try await central.connect(record.peripheralID, autoReconnect: true, timeout: nil)
        guard generation == attempt, !Task.isCancelled else {
            await central.cancelConnection(record.peripheralID)
            throw CancellationError()
        }
        let transport = RecordingTransport(raw, logger: logger)
        let linkEvents = transport.linkEvents()
        let driver: any CameraDriver
        let identity: CameraIdentity
        let client: ClientIdentity
        let mode: SessionMode
        do {
            guard let made = registry.makeDriver(id: record.driverID, transport: transport) else {
                throw SessionError.unknownDriver(record.driverID)
            }
            driver = made
            identity = try identities.cameraIdentity(for: record.id) ?? .bondOnly
            client = try identities.clientIdentity()
            mode = await stores.settings.load().sessionMode
            await driver.setFeatures(remote: mode.usesRemote, geotag: mode.usesGeotag)
            try await stores.cameras.update { records in
                if let index = records.firstIndex(where: { $0.id == record.id }) {
                    records[index].lastConnectedAt = Date()
                }
            }
        } catch {
            await central.cancelConnection(record.peripheralID)
            throw error
        }
        let session = CameraSession(record: record, central: central, transport: transport, driver: driver,
                                    identity: identity, client: client, logger: logger,
                                    configuration: await sequencerConfiguration(),
                                    rescanOnDisconnect: rescanOnDisconnect, linkEvents: linkEvents)
        guard await install(session, generation: attempt, mode: mode) else { throw CancellationError() }
        // Geotag only starts geotagging when the link becomes ready, now or later.
        await session.startConnected()
    }

    // MARK: Mode

    /// Geotag only, remote only, or both. Saved on this device and applied to
    /// the running session at once.
    public func setMode(_ mode: SessionMode) async throws {
        try await stores.settings.update { $0.sessionMode = mode }
        guard let session else { return }
        // Changing the mode is use of the camera (architecture doc § Auto disconnect).
        autoDisconnect?.activity(now: .now)
        await session.setFeatures(mode)
        switch mode {
        case .remoteOnly:
            await stopGeotag()
        case .geotagOnly:
            await session.stopIntervalometer()
            await session.sequencer.handle(.sceneInactive)
            wantsGeotag = true
            if await session.currentState() == .ready { await startGeotag() }
        case .remoteAndGeotag:
            break
        }
    }

    public func mode() async -> SessionMode {
        await stores.settings.load().sessionMode
    }

    /// Ends the session: releases every button, drops the link and cancels
    /// the pending connect, so the camera is free for another device.
    public func endSession() async {
        generation += 1
        let pending = activating
        activation?.cancel()
        activation = nil
        activating = nil
        autoDisconnectTask?.cancel()
        autoDisconnectTask = nil
        autoDisconnect = nil
        wantsGeotag = false
        guard let session else {
            // A connect that never completed: cancel the pending connect.
            guard let pending else { return }
            let central: any BluetoothCentral = pending.isDemo ? demoCentral : self.central
            await central.cancelConnection(pending.peripheralID)
            current = SessionSnapshot()
            sessionUpdates.yield(current)
            _ = try? await stores.settings.update { $0.lastActiveCameraID = nil }
            return
        }
        self.session = nil
        for task in forwarders { task.cancel() }
        forwarders.removeAll()
        // Published before the teardown, which can wait on writes to a camera
        // that is gone: the app, its Live Activity and tile show the end at once.
        current = SessionSnapshot()
        sessionUpdates.yield(current)
        await stores.tracks.finish()
        shutterUpdates.yield(ShutterSnapshot())
        geotagUpdates.yield(GeotagSnapshot())
        intervalometerUpdates.yield(IntervalometerSnapshot())
        // Location goes off now too: the teardown below stops geotagging only
        // after shots and camera writes finish, and until then iOS keeps the
        // location indicator in the Dynamic Island.
        await (session.record.isDemo ? demoLocation : location).stop()
        // Forgotten before the teardown, which can wait on a camera that is
        // gone: if the app stops during it, the next launch must not resume
        // a session the user ended (Settings › Auto reconnect resumes only an
        // interrupted one).
        _ = try? await stores.settings.update {
            $0.lastActiveCameraID = nil
            $0.openGeotagSession = false
        }
        let previous = teardown
        let ending = Task {
            await previous?.value
            await session.end()
        }
        teardown = ending
        await ending.value
    }

    /// Re-opens, at launch, the session that was running when the app last
    /// stopped (Settings › Auto reconnect), with its geotagging if that was
    /// on (architecture doc § Geotag defaults: Core Location relaunches the
    /// app while the session is outstanding). With Auto reconnect off, the
    /// old session is dropped instead. Returns `true` when one was restored.
    @discardableResult
    public func restoreSession() async -> Bool {
        let settings = await stores.settings.load()
        let restored = await central.restoredPeripherals()
        guard let id = settings.lastActiveCameraID,
              let record = await stores.cameras.load().first(where: { $0.id == id }) else {
            await release(restored, keeping: nil)
            return false
        }
        guard settings.autoReconnect else {
            _ = try? await stores.settings.update {
                $0.lastActiveCameraID = nil
                $0.openGeotagSession = false
            }
            await release(restored, keeping: nil)
            return false
        }
        await logger.log(.note, note: "restoring the session on \(record.name)")
        await release(restored, keeping: record.peripheralID)
        do {
            try await activate(record)
            if settings.openGeotagSession { await startGeotag() }
            return true
        } catch {
            await logger.log(.error, note: "restore failed: \(error)")
            return false
        }
    }

    /// Cancels the connects Core Bluetooth restored for cameras no session
    /// uses, so an app that resumes nothing does not hold a camera another
    /// device could use.
    private func release(_ restored: [UUID], keeping kept: UUID?) async {
        for id in restored where id != kept {
            await logger.log(.note, note: "releasing a restored connection nothing uses")
            await central.cancelConnection(id)
        }
    }

    // MARK: Geotag

    /// Starts geotagging on the active camera. The session record stays open
    /// until `stopGeotag()` or `endSession()`.
    @discardableResult
    public func startGeotag() async -> GeotagStatus {
        guard let session else { return .failed(.other("No active camera")) }
        autoDisconnect?.activity(now: .now)
        guard await stores.settings.load().sessionMode.usesGeotag else {
            return .failed(.other("Geotag is off: the mode is Remote only"))
        }
        guard self.session === session else { return .failed(.other("No active camera")) }
        wantsGeotag = true
        let source = session.record.isDemo ? demoLocation : location
        let status = await session.startGeotag(source: source, configuration: await geotagConfiguration())
        let open: Bool
        switch status {
        case .failed, .off: open = false
        default: open = true
        }
        _ = try? await stores.settings.update { $0.openGeotagSession = open }
        return status
    }

    public func stopGeotag() async {
        wantsGeotag = false
        await session?.stopGeotag()
        _ = try? await stores.settings.update { $0.openGeotagSession = false }
    }

    /// Per-camera *Keep camera awake*.
    public func setKeepAwake(_ keepAwake: Bool, for record: CameraRecord) async throws {
        try await stores.cameras.update { records in
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                records[index].keepAwake = keepAwake
            }
        }
        await settingsChanged()
    }

    /// Removes a camera from this device. The bond itself is removed in
    /// Settings › Bluetooth (and on the camera); the UI says so.
    public func forget(_ record: CameraRecord) async throws {
        if session?.record.id == record.id || activating?.id == record.id { await endSession() }
        try identities.setCameraIdentity(nil, for: record.id)
        try await stores.cameras.update { records in records.removeAll { $0.id == record.id } }
    }

    public func activeCamera() -> CameraRecord? { session?.record }

    public func isGeotagging() async -> Bool {
        await session?.isGeotagging ?? false
    }

    /// Ends and re-opens the active camera's session: the *Retry* button for
    /// *Busy* and failed links.
    public func retry() async throws {
        // A failed activation leaves no session, only its camera in the snapshot.
        guard let record = session?.record ?? activating ?? current.camera else {
            throw SessionError.noActiveSession
        }
        await endSession()
        try await activate(record)
    }

    /// The app became active (wrist raise, app opened): check a long-idle link.
    public func sceneBecameActive() async {
        await session?.checkLiveness()
    }

    // MARK: Intervalometer

    public func startIntervalometer(_ plan: IntervalometerPlan) async throws {
        guard let session else { throw SessionError.noActiveSession }
        let mode = await stores.settings.load().sessionMode
        guard mode.usesRemote else { throw SessionError.notInMode(mode) }
        autoDisconnect?.activity(now: .now)
        try await stores.settings.update { $0.intervalometer = plan }
        await session.startIntervalometer(plan)
    }

    public func stopIntervalometer() async {
        await session?.stopIntervalometer()
    }

    // MARK: Shutter

    public func shutter(_ input: ShutterInput) async {
        guard let session else { return }
        if input != .sceneInactive, await !stores.settings.load().sessionMode.usesRemote { return }
        if input != .sceneInactive { autoDisconnect?.activity(now: .now) }
        await session.touch()
        await session.sequencer.handle(input)
    }

    // MARK: Intents

    /// *Shoot* from a shortcut, the Smart Stack tile or a control (product spec §
    /// Shortcuts, Controls and the Action Button). Focuses, fires and waits
    /// for the result at most `timeout`, so the intent answers within 8 s;
    /// a shot still running then is reported as sent. The release delay and
    /// bulb mode apply only while a geotag session keeps the app running, so
    /// a suspended app never leaves the shutter open; otherwise the shot
    /// fires at once.
    public func shootFromIntent(timeout: Duration = .seconds(7)) async throws -> IntentShot {
        guard let session else { throw SessionError.noActiveSession }
        let settings = await stores.settings.load()
        guard settings.sessionMode.usesRemote else { throw SessionError.notInMode(settings.sessionMode) }
        guard await session.currentState() == .ready else { throw SessionError.notReady }
        autoDisconnect?.activity(now: .now)
        await session.touch()
        let sequencer = session.sequencer
        // A running countdown or an open bulb takes the shot as a cancel or
        // a close, whatever the mode; say what happened.
        var gestureDecides = await sequencer.isHoldingShutter
        let bulbMode = await sequencer.bulbMode
        if !gestureDecides, await session.isGeotagging {
            gestureDecides = bulbMode || settings.releaseDelaySeconds > 0
        } else if !gestureDecides, bulbMode, sequencer.driver.shotScript.unlatchToggles {
            // The camera is in BULB or Time, where one press opens the
            // shutter and only another closes it.
            throw SessionError.bulbNeedsApp
        }
        if gestureDecides {
            switch await sequencer.shoot() {
            case .bulbClosed: return .bulbClosed
            case .countdownCancelled: return .countdownCancelled
            case .bulbStarted: return .bulb(seconds: settings.bulbSeconds, delay: settings.releaseDelaySeconds)
            case .countdownStarted: return .countdown(seconds: settings.releaseDelaySeconds)
            case .shotStarted, .ignored: return .stillRunning
            }
        }
        let shot = Task { await sequencer.frame(focus: true, exposure: nil, readyTimeout: nil, stoppable: false) }
        guard let result = await value(of: shot, within: timeout) else { return .stillRunning }
        return .result(result)
    }

    /// *Focus* from a shortcut: the half-press, held for the focus hold time.
    public func focusFromIntent() async throws {
        guard let session else { throw SessionError.noActiveSession }
        let mode = await stores.settings.load().sessionMode
        guard mode.usesRemote else { throw SessionError.notInMode(mode) }
        guard await session.currentState() == .ready else { throw SessionError.notReady }
        autoDisconnect?.activity(now: .now)
        await session.touch()
        await session.sequencer.handle(.focus)
    }

    /// Re-reads settings into the running sequencer.
    public func settingsChanged() async {
        autoReconnect = await stores.settings.load().autoReconnect
        guard let session else { return }
        let minutes = await stores.settings.load().autoDisconnectMinutes
        if autoDisconnect?.minutes != minutes {
            var fresh = AutoDisconnect(minutes: minutes, unit: autoDisconnectUnit, now: .now)
            fresh.link(await session.currentState(), now: .now)
            autoDisconnect = fresh
        }
        await session.sequencer.setConfiguration(await sequencerConfiguration())
        await session.setGeotagConfiguration(await geotagConfiguration())
    }

    // MARK: Private

    /// Makes `session` the active one, unless a newer activate, pair or
    /// end came first: then it is ended and `false` returned, so no second
    /// session is left running.
    private func install(_ session: CameraSession, generation installing: Int, mode: SessionMode) async -> Bool {
        guard generation == installing, self.session == nil else {
            await session.end()
            return false
        }
        self.session = session
        current.ended = nil
        // Remembered only once the session is installed: a connect that an
        // End session overtook must not leave a camera for the next launch to
        // resume. An end during this write queues its own clear after it.
        _ = try? await stores.settings.update { $0.lastActiveCameraID = session.record.id }
        wantsGeotag = mode == .geotagOnly
        autoReconnect = await stores.settings.load().autoReconnect
        if autoDisconnect == nil { await startAutoDisconnect(for: session.record.id) }
        let record = session.record
        let shutterUpdates = self.shutterUpdates
        let states = session.linkStates()
        let snapshots = session.sequencer.snapshots()
        let geotagUpdates = self.geotagUpdates
        let geotags = session.geotagSnapshots()
        let intervalometerUpdates = self.intervalometerUpdates
        let runs = session.intervalometer.snapshots()
        let noticeSets = session.noticeSets()
        // The session's GPS track starts now; its file appears with the first fix.
        let tracks = stores.tracks
        await tracks.begin(startedAt: Date())
        let fixes = session.geotagFixes()
        let logger = self.logger
        forwarders = [
            Task {
                for await fix in fixes {
                    do {
                        try await tracks.append(fix)
                    } catch {
                        await logger.log(.error, note: "track write failed: \(error)")
                    }
                }
            },
            Task {
                for await snapshot in geotags {
                    geotagUpdates.yield(snapshot)
                }
            },
            Task {
                for await snapshot in runs {
                    intervalometerUpdates.yield(snapshot)
                }
            },
            Task { [weak self] in
                for await notices in noticeSets {
                    await self?.publish(notices: notices)
                }
            },
            Task { [weak self] in
                for await state in states {
                    await self?.publish(camera: record, link: state)
                }
            },
            Task {
                // Each press that went out marks the session's GPS track.
                var sent = 0
                for await snapshot in snapshots {
                    shutterUpdates.yield(snapshot)
                    if snapshot.sent > sent {
                        for _ in sent..<snapshot.sent { try? await tracks.markShot(at: Date()) }
                    }
                    sent = snapshot.sent
                }
            },
        ]
        return true
    }

    /// Starts the auto-disconnect policy and its periodic check. The camera
    /// counts as unreachable from now until its link is ready.
    private func startAutoDisconnect(for cameraID: UUID) async {
        let minutes = await stores.settings.load().autoDisconnectMinutes
        autoDisconnect = AutoDisconnect(minutes: minutes, unit: autoDisconnectUnit, now: .now)
        autoDisconnectTask?.cancel()
        let check = autoDisconnectCheck
        autoDisconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: check)
                guard !Task.isCancelled else { return }
                await self?.checkAutoDisconnect(cameraID)
            }
        }
    }

    /// Ends the session (or the activation still waiting for the camera)
    /// when auto disconnect says so.
    private func checkAutoDisconnect(_ cameraID: UUID) async {
        guard autoDisconnect != nil else { return }
        let camera: CameraRecord
        let busy: Bool
        if let session {
            guard session.record.id == cameraID else { return }
            camera = session.record
            busy = await isBusy(session)
        } else if let activating, activating.id == cameraID {
            camera = activating
            busy = false
        } else {
            return
        }
        guard let reason = autoDisconnect?.check(now: .now, busy: busy) else { return }
        if let session, await session.sequencer.mayHaveShutterOpen {
            // As with a lost link: only the reconnect can close the bulb.
            await logger.log(.note, note: "auto disconnect held: a bulb may be open")
            return
        }
        await logger.log(.note, note: "auto disconnect: \(reason)")
        await endSession()
        current = SessionSnapshot(camera: camera, link: .ended, ended: reason)
        sessionUpdates.yield(current)
    }

    /// Something is running that counts as activity. A held half-press is
    /// not: with AF hold on a camera that never confirms focus it would
    /// keep the session alive forever.
    private func isBusy(_ session: CameraSession) async -> Bool {
        if await session.isGeotagging { return true }
        if await session.intervalometer.currentSnapshot().isRunning { return true }
        switch await session.sequencer.currentSnapshot().phase {
        case .countdown, .bulbOpen, .shooting: return true
        default: return false
        }
    }

    private func publish(camera: CameraRecord, link: LinkState) {
        guard session?.record.id == camera.id else { return }
        autoDisconnect?.link(link, now: .now)
        current.camera = camera
        current.link = link
        sessionUpdates.yield(current)
        if link == .ready, wantsGeotag {
            Task { await self.resumeGeotag(on: camera.id) }
        }
        if link == .reconnecting, !autoReconnect {
            Task { await self.endAfterLinkLoss(camera) }
        }
    }

    /// Auto reconnect is off and the link dropped: the session ends, unless
    /// a bulb may still be open, which only the reconnect can close.
    private func endAfterLinkLoss(_ camera: CameraRecord) async {
        guard !autoReconnect, let session, session.record.id == camera.id,
              await session.currentState() == .reconnecting else { return }
        if await session.sequencer.mayHaveShutterOpen {
            await logger.log(.note, note: "link lost with a bulb open; reconnecting to close it")
            return
        }
        await logger.log(.note, note: "link lost with auto reconnect off; ending the session")
        await endSession()
        current = SessionSnapshot(camera: camera, link: .ended, ended: .linkLost)
        sessionUpdates.yield(current)
    }

    /// The link became ready (now or after a reconnect) while geotagging is
    /// wanted: start it if it is not running.
    private func resumeGeotag(on cameraID: UUID) async {
        guard wantsGeotag, let session, session.record.id == cameraID,
              await session.currentState() == .ready, await !session.isGeotagging else { return }
        await startGeotag()
    }

    private func publish(notices: Set<SessionNotice>) {
        guard session != nil else { return }
        current.notices = notices
        sessionUpdates.yield(current)
    }

    private func geotagConfiguration() async -> GeotagConfiguration {
        let settings = await stores.settings.load()
        var configuration = GeotagConfiguration()
        configuration.interval = .seconds(min(max(settings.geotagIntervalSeconds, 5), 60))
        if let session {
            let id = session.record.id
            configuration.keepAwake = await stores.cameras.load().first { $0.id == id }?.keepAwake ?? false
        }
        return configuration
    }

    private func sequencerConfiguration() async -> SequencerConfiguration {
        let settings = await stores.settings.load()
        var configuration = SequencerConfiguration()
        configuration.afHold = settings.afHold
        configuration.tapShoots = settings.tapToShoot
        configuration.focusGrace = .seconds(min(max(settings.focusGraceSeconds, 1), 10))
        configuration.releaseDelay = settings.releaseDelaySeconds > 0
            ? .seconds(min(settings.releaseDelaySeconds, 60)) : nil
        configuration.bulbDuration = settings.bulbSeconds > 0
            ? min(.seconds(settings.bulbSeconds), SequencerConfiguration.bulbLimit) : nil
        return configuration
    }
}
