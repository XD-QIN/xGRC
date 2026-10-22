import BLEKit
import CameraKit
import Foundation
import LocationKit
import Persistence

/// Link state of the active camera, as the camera row and status strip show it
/// (product spec § States & errors). Mirrors DesignKit's `LinkIndicator`.
public enum LinkState: Hashable, Sendable {
    case connecting
    /// Waiting for the user to confirm pairing.
    case bonding
    case registering
    case ready
    /// The OS keeps a pending connect; the camera is off or out of range.
    case reconnecting
    /// No link after the session window; still trying.
    case outOfRange
    /// Linked to another phone, watch or app.
    case busy
    /// The camera no longer recognises this device.
    case pairAgain
    /// A characteristic the driver needs is gone after rediscovery (firmware update).
    case firmwareChanged
    case failed(String)
    case ended
}

/// A short sentence for a failure the app shows as is (product spec §
/// States & errors); the raw error goes to the transcript.
func describeFailure(_ error: Error) -> String {
    switch error {
    case GATTError.bluetoothUnavailable(.unauthorized), SessionError.bluetooth(.unauthorized):
        "xGRC needs Bluetooth. Allow it in Settings."
    case GATTError.bluetoothUnavailable, SessionError.bluetooth:
        "Bluetooth is off"
    case CameraError.remoteControlOff:
        "Turn on Bluetooth Rmt Ctrl on the camera"
    case CameraError.unsupported:
        "This camera or its current Bluetooth setting is not supported"
    case GATTError.timeout, CameraError.transport(.timeout):
        "The camera did not answer in time"
    case GATTError.disconnected, CameraError.transport(.disconnected):
        "The camera disconnected"
    case SessionError.unknownDriver:
        "This version of xGRC does not support this camera"
    default:
        "Something went wrong talking to the camera. Try again."
    }
}

/// Conditions the session reports alongside its link state (product spec § States & errors).
public enum SessionNotice: Hashable, Sendable {
    /// The watch keeps losing the camera: reduced-range mode after repeated link timeouts.
    case reducedRange
    /// The background wake-up budget is nearly spent (`false`) or spent (`true`).
    case backgroundBudget(exceeded: Bool)
}

/// One camera, one link, one sequencer, at most one geotag stream (architecture doc § Key abstractions:
/// `CameraSession` owns the state machine and runs `driver.reconnect()` on
/// every OS reconnect before any queued command).
public actor CameraSession {
    public let record: CameraRecord
    public let sequencer: ShotSequencer<ContinuousClock>

    private let central: any BluetoothCentral
    private let transport: any GATTTransport
    private let driver: any CameraDriver
    private let identity: CameraIdentity
    private let client: ClientIdentity
    private let logger: TranscriptLogger
    private let states = Broadcaster<LinkState>(replayLast: true)
    private var state: LinkState = .connecting
    /// Subscribed when the link came up, before pairing or registering, so
    /// a drop or a Service Changed in between is not lost.
    private let linkEvents: AsyncStream<LinkEvent>
    private var linkTask: Task<Void, Never>?
    /// A registration runs; another request runs it once more afterwards.
    private var isRegistering = false
    private var registerAgain = false
    /// *Pair again* or a firmware change cancelled the reconnect, once.
    private var stoppedReconnecting = false
    private var reconnectTask: Task<Void, Never>?
    private var connectGeneration = 0
    private var windowTask: Task<Void, Never>?
    private var isEnded = false
    private var geotag: GeoTagStreamer<ContinuousClock>?
    /// A geotag start in flight; a second `startGeotag` waits for it
    /// instead of creating another streamer.
    private var geotagStart: Task<GeotagStatus, Never>?
    private var geotagForwarder: Task<Void, Never>?
    private let geotagUpdates = Broadcaster<GeotagSnapshot>(replayLast: true)
    private let fixUpdates = Broadcaster<GeoFix>()
    public let intervalometer: Intervalometer<ContinuousClock>
    private let noticeUpdates = Broadcaster<Set<SessionNotice>>(replayLast: true)
    private var notices: Set<SessionNotice> = []
    private var recentTimeouts: [ContinuousClock.Instant] = []
    private var rescanTask: Task<Void, Never>?
    /// One replacement per disconnect episode, so a camera that advertises
    /// but will not connect is not hammered.
    private var rescanUsed = false
    private var lastActivity = ContinuousClock.now
    /// Foreground rescan on disconnect (watch: architecture doc § Reconnect policy).
    private let rescanOnDisconnect: Bool

    /// How long a reconnect may take before the UI says "Camera off or out of range".
    public static let sessionWindow: Duration = .seconds(60)
    /// Registration retries after the camera connected but rejected the handshake.
    static let registrationBackoff: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]

    /// Three link timeouts inside this window raise the reduced-range banner.
    static let reducedRangeWindow: Duration = .seconds(10 * 60)
    /// After this long without traffic, a liveness read runs before trusting *Ready*.
    static let livenessIdle: Duration = .seconds(60)
    /// How long a rescan sees the camera advertising before replacing the pending connect.
    static let rescanGrace: Duration = .seconds(2)

    init(record: CameraRecord, central: any BluetoothCentral, transport: any GATTTransport,
         driver: any CameraDriver, identity: CameraIdentity, client: ClientIdentity,
         logger: TranscriptLogger, configuration: SequencerConfiguration, rescanOnDisconnect: Bool = false,
         linkEvents: AsyncStream<LinkEvent>? = nil) {
        self.record = record
        self.linkEvents = linkEvents ?? transport.linkEvents()
        self.central = central
        self.transport = transport
        self.driver = driver
        self.identity = identity
        self.client = client
        self.logger = logger
        self.sequencer = ShotSequencer(driver: driver, clock: ContinuousClock(), configuration: configuration)
        self.intervalometer = Intervalometer(sequencer: sequencer, clock: ContinuousClock())
        self.rescanOnDisconnect = rescanOnDisconnect
        noticeUpdates.yield([])
    }

    public nonisolated func noticeSets() -> AsyncStream<Set<SessionNotice>> {
        noticeUpdates.stream()
    }

    /// Applies the app's mode to the driver; takes effect on the next reconnect.
    func setFeatures(_ mode: SessionMode) async {
        await driver.setFeatures(remote: mode.usesRemote, geotag: mode.usesGeotag)
    }

    // MARK: Intervalometer

    func startIntervalometer(_ plan: IntervalometerPlan) async {
        await intervalometer.start(plan)
        let total = plan.frames.map(String.init) ?? "∞"
        await logger.log(.note, note: "intervalometer start: \(plan.intervalSeconds) s × \(total)")
    }

    func stopIntervalometer() async {
        await intervalometer.stop()
    }

    // MARK: Liveness

    /// Marks traffic on the link (a shot, a geotag push).
    func touch() {
        lastActivity = .now
    }

    /// product spec § States & errors, "camera asleep while the app still shows
    /// Connected": after more than 60 s idle, one read with a timeout before
    /// trusting *Ready*; a failure forces a reconnect.
    func checkLiveness() async {
        guard state == .ready, lastActivity.duration(to: .now) > Self.livenessIdle else { return }
        let transport = self.transport
        do {
            _ = try await withTimeout(.seconds(3)) { try await transport.readRSSI() }
            lastActivity = .now
        } catch {
            await logger.log(.note, note: "liveness read failed: \(error); reconnecting")
            await central.cancelConnection(record.peripheralID)
        }
    }

    public nonisolated func linkStates() -> AsyncStream<LinkState> {
        states.stream()
    }

    public func currentState() -> LinkState { state }

    public nonisolated func geotagSnapshots() -> AsyncStream<GeotagSnapshot> {
        geotagUpdates.stream()
    }

    /// The fixes geotagging accepted, across every start and stop.
    public nonisolated func geotagFixes() -> AsyncStream<GeoFix> {
        fixUpdates.stream()
    }

    public var isGeotagging: Bool {
        get async { await geotag?.currentSnapshot().isActive ?? false }
    }

    // MARK: Geotag

    /// Starts a geotag stream on this camera. A second call while one runs
    /// returns its status.
    @discardableResult
    func startGeotag(source: any LocationSource, configuration: GeotagConfiguration) async -> GeotagStatus {
        if let geotagStart { return await geotagStart.value }
        guard !isEnded else { return .failed(.other("The session ended")) }
        let previous = geotag
        let start = Task { () -> GeotagStatus in
            if let previous, await previous.currentSnapshot().isActive {
                return await previous.currentSnapshot().status
            }
            return await self.startStreamer(source: source, configuration: configuration)
        }
        geotagStart = start
        let status = await start.value
        geotagStart = nil
        return status
    }

    private func startStreamer(source: any LocationSource, configuration: GeotagConfiguration) async -> GeotagStatus {
        let streamer = GeoTagStreamer(driver: driver, source: source, clock: ContinuousClock(),
                                      configuration: configuration)
        geotag = streamer
        geotagForwarder?.cancel()
        let updates = geotagUpdates
        let snapshots = streamer.snapshots()
        let fixUpdates = fixUpdates
        let fixes = streamer.validFixes()
        geotagForwarder = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await snapshot in snapshots { updates.yield(snapshot) } }
                group.addTask { for await fix in fixes { fixUpdates.yield(fix) } }
            }
        }
        if state != .ready { await streamer.linkLost() }
        let status = await streamer.start()
        await logger.log(.note, note: "geotag start: \(status)")
        if isEnded { await streamer.stop() }
        return status
    }

    func stopGeotag() async {
        // A start in flight finishes first, so its lock is released too.
        if let geotagStart { _ = await geotagStart.value }
        guard let geotag else { return }
        await geotag.stop()
        let pushes = await geotag.currentSnapshot().pushes
        await logger.log(.note, note: "geotag stop: \(pushes) pushes")
    }

    func setGeotagConfiguration(_ configuration: GeotagConfiguration) async {
        await geotag?.setConfiguration(configuration)
    }

    /// Starts on a link that is already registered (right after pairing).
    func startRegistered() async {
        await sequencer.start()
        guard !isEnded else { return }
        watchLink()
        set(.ready)
    }

    /// Starts on a fresh connection: registers, then becomes ready.
    func startConnected() async {
        await sequencer.start()
        guard !isEnded else { return }
        watchLink()
        await register()
    }

    func end() async {
        guard !isEnded else { return }
        isEnded = true
        linkTask?.cancel()
        reconnectTask?.cancel()
        windowTask?.cancel()
        // The intervalometer first: an open bulb frame would otherwise hold
        // `idle()` for the rest of its exposure.
        await intervalometer.stop()
        await sequencer.handle(.sceneInactive)
        await sequencer.idle()
        await sequencer.stop()
        await stopGeotag()
        geotagForwarder?.cancel()
        rescanTask?.cancel()
        await driver.disconnect()
        await central.cancelConnection(record.peripheralID)
        set(.ended)
        states.finish()
    }

    // MARK: Private

    private func watchLink() {
        let events = linkEvents
        linkTask = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: LinkEvent) async {
        guard !isEnded else { return }
        switch event {
        case .disconnected(let reason, let isReconnecting):
            await sequencer.linkLost()
            await geotag?.linkLost()
            await intervalometer.linkLost()
            guard !isEnded else { return }
            if state == .pairAgain || state == .firmwareChanged {
                // The camera dropped a bond it no longer has (the drop follows
                // `.bondRemoved`), or the firmware changed: reconnecting cannot
                // help, so *Pair again* stays and the OS stops trying.
                guard !stoppedReconnecting else { return }
                stoppedReconnecting = true
                await central.cancelConnection(record.peripheralID)
                return
            }
            noteDrop(reason)
            set(.reconnecting)
            startWindow()
            if !isReconnecting { pendingConnect() }
            startRescan()
        case .reconnected:
            await register()
        case .servicesModified:
            await register()
        case .bondRemoved:
            set(.pairAgain)
        case .backgroundBudget(let exceeded):
            await logger.log(.note, note: "background wake-up budget: \(event)")
            notices.remove(.backgroundBudget(exceeded: !exceeded))
            notices.insert(.backgroundBudget(exceeded: exceeded))
            noticeUpdates.yield(notices)
        }
    }

    /// Repeated supervision timeouts put the watch in reduced-range mode.
    private func noteDrop(_ reason: LinkReason) {
        guard reason == .connectionTimeout else { return }
        let now = ContinuousClock.now
        recentTimeouts = recentTimeouts.filter { $0.duration(to: now) < Self.reducedRangeWindow } + [now]
        if recentTimeouts.count >= 3, notices.insert(.reducedRange).inserted {
            noticeUpdates.yield(notices)
        }
    }

    /// Foreground rescan alongside the pending connect: if the camera is seen
    /// advertising and the OS has not reconnected shortly after, the pending
    /// connect is replaced by a fresh one (architecture doc § Reconnect policy).
    private func startRescan() {
        guard rescanOnDisconnect, !rescanUsed else { return }
        rescanTask?.cancel()
        let central = self.central
        let peripheralID = record.peripheralID
        let window = Self.sessionWindow
        let grace = Self.rescanGrace
        rescanTask = Task { [weak self] in
            // The window is its own timer: with nothing advertising, the scan
            // yields nothing to check a deadline against.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    let stream = central.scan()
                    var firstSeen: ContinuousClock.Instant?
                    for await advertisement in stream {
                        guard !Task.isCancelled, let self else { return }
                        guard advertisement.peripheralID == peripheralID else { continue }
                        if await self.currentState() == .ready { return }
                        let seen = firstSeen ?? .now
                        firstSeen = seen
                        if seen.duration(to: .now) >= grace {
                            await self.replacePendingConnect()
                            return
                        }
                    }
                }
                group.addTask { try? await Task.sleep(for: window) }
                await group.next()
                group.cancelAll()
            }
        }
    }

    private func replacePendingConnect() async {
        guard !isEnded, state != .ready, !rescanUsed else { return }
        rescanUsed = true
        await logger.log(.note, note: "rescan found the camera advertising; replacing the pending connect")
        if let old = reconnectTask {
            connectGeneration += 1
            reconnectTask = nil
            old.cancel()
            await old.value
        }
        await central.cancelConnection(record.peripheralID)
        guard !isEnded, state != .ready else { return }
        pendingConnect()
    }

    /// The link went down without an OS auto-reconnect: queue a pending
    /// connect. At most one is outstanding.
    private func pendingConnect() {
        guard reconnectTask == nil, !isEnded else { return }
        connectGeneration += 1
        let generation = connectGeneration
        let central = self.central
        let peripheralID = record.peripheralID
        reconnectTask = Task { [weak self] in
            while true {
                do {
                    _ = try await central.connect(peripheralID, autoReconnect: true, timeout: nil)
                    await self?.connectFinished(nil, generation: generation)
                } catch GATTError.bluetoothUnavailable {
                    // Bluetooth is off or resetting: connect again once it is
                    // back on (Control Center off and on), however long it takes.
                    guard await Self.poweredOn(central) else { return }
                    continue
                } catch {
                    await self?.connectFinished(error, generation: generation)
                }
                return
            }
        }
    }

    /// Waits until the central reports `.poweredOn`; `false` when cancelled.
    private static func poweredOn(_ central: any BluetoothCentral) async -> Bool {
        for await state in central.stateUpdates() where state == .poweredOn {
            return !Task.isCancelled
        }
        return false
    }

    private func connectFinished(_ error: Error?, generation: Int) async {
        guard generation == connectGeneration else { return }
        reconnectTask = nil
        guard !isEnded else { return }
        if let error {
            if error is CancellationError { return }
            fail(error)
        } else {
            await register()
        }
    }

    private func startWindow() {
        windowTask?.cancel()
        windowTask = Task { [weak self] in
            try? await Task.sleep(for: Self.sessionWindow)
            guard !Task.isCancelled else { return }
            await self?.windowExpired()
        }
    }

    private func windowExpired() {
        if state == .reconnecting { set(.outOfRange) }
    }

    /// One registration at a time: a reconnect and a Service Changed that
    /// arrive together would otherwise interleave two `driver.reconnect()`s.
    /// A request while one runs makes it run once more when it ends.
    private func register() async {
        guard !isEnded else { return }
        guard !isRegistering else {
            registerAgain = true
            return
        }
        isRegistering = true
        defer { isRegistering = false }
        repeat {
            registerAgain = false
            await registerOnce()
        } while registerAgain && !isEnded
    }

    /// `driver.reconnect()` with the 2 / 4 / 8 s backoff. When every try
    /// fails: *Pair again* only for a camera that may have dropped us, a
    /// setting to change for Rmt Ctrl off or an unsupported mode, and a drop
    /// and reconnect for a camera that was too slow to answer.
    /// `end()` can run at any await: nothing changes after it.
    private func registerOnce() async {
        guard !isEnded else { return }
        windowTask?.cancel()
        set(.registering)
        var attempt = 0
        while true {
            do {
                try await driver.reconnect(identity: identity, client: client)
                guard !isEnded else { return }
                await sequencer.linkRestored()
                guard !isEnded else { return }
                rescanTask?.cancel()
                rescanUsed = false
                lastActivity = .now
                set(.ready)
                await geotag?.linkRestored()
                guard !isEnded else { return }
                await intervalometer.linkRestored()
                return
            } catch {
                guard !isEnded else { return }
                if let terminal = Self.terminalState(for: error) {
                    set(terminal)
                    return
                }
                guard attempt < Self.registrationBackoff.count else {
                    await registrationFailed(error)
                    return
                }
                await logger.log(.error, note: "registration failed: \(error); retrying")
                try? await Task.sleep(for: Self.registrationBackoff[attempt])
                guard !isEnded else { return }
                attempt += 1
            }
        }
    }

    private func registrationFailed(_ error: Error) async {
        await logger.log(.error, note: "registration failed: \(error); giving up")
        switch error {
        case CameraError.remoteControlOff, CameraError.unsupported:
            set(.failed(describeFailure(error)))
        case CameraError.transport(.timeout), GATTError.timeout:
            // Dropped, so the link event queues a fresh connect.
            set(.reconnecting)
            await central.cancelConnection(record.peripheralID)
        default:
            set(.pairAgain)
        }
    }

    private func fail(_ error: Error) {
        guard !isEnded else { return }
        if Self.terminalState(for: error) == nil {
            let logger = self.logger
            let note = "link failed: \(error)"
            Task { await logger.log(.error, note: note) }
        }
        set(Self.terminalState(for: error) ?? .failed(describeFailure(error)))
    }

    static func terminalState(for error: Error) -> LinkState? {
        switch error {
        case CameraError.pairAgain,
             CameraError.transport(.peerRemovedPairing),
             CameraError.transport(.insufficientAuthentication),
             GATTError.peerRemovedPairing,
             GATTError.insufficientAuthentication:
            .pairAgain
        case CameraError.busy:
            .busy
        case CameraError.missingCharacteristic:
            .firmwareChanged
        case CameraError.transport(.disconnected), GATTError.disconnected:
            .reconnecting
        default:
            nil
        }
    }

    private func set(_ new: LinkState) {
        // After `end()` the state stays `.ended`.
        guard state != new, !isEnded || new == .ended else { return }
        state = new
        states.yield(new)
    }
}
