import BLEKit
import CameraKit
import Foundation
import LocationKit
import Persistence
@testable import SessionKit
import Testing

/// A central whose connects wait like a pending connect to a camera that is
/// off, until the test completes or the caller cancels them.
final class PendingCentral: BluetoothCentral, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<any GATTTransport, Error>] = [:]
    private var transports: [UUID: any GATTTransport] = [:]
    private(set) var cancelled: [UUID] = []
    /// Peripherals state restoration handed back at launch.
    var restored: [UUID] = []

    func setTransport(_ transport: any GATTTransport, for id: UUID) {
        lock.withLock { transports[id] = transport }
    }

    var pending: Set<UUID> { lock.withLock { Set(waiters.keys) } }

    /// The camera comes into range: the pending connect for `id` completes.
    func complete(_ id: UUID) {
        let (waiter, transport) = lock.withLock { (waiters.removeValue(forKey: id), transports[id]) }
        if let transport { waiter?.resume(returning: transport) }
    }

    func currentState() async -> CentralState { .poweredOn }
    func stateUpdates() -> AsyncStream<CentralState> { AsyncStream { $0.yield(.poweredOn) } }
    func scan() -> AsyncStream<Advertisement> { AsyncStream { _ in } }
    func connectedPeripherals(withServices services: [UUID]) async -> [UUID] { [] }
    func restoredPeripherals() async -> [UUID] { lock.withLock { restored } }

    func connect(_ peripheralID: UUID, autoReconnect: Bool, timeout: Duration?) async throws -> any GATTTransport {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { waiters[peripheralID] = continuation }
            }
        } onCancel: {
            fail(peripheralID)
        }
    }

    func cancelConnection(_ peripheralID: UUID) async {
        lock.withLock { cancelled.append(peripheralID) }
        fail(peripheralID)
    }

    private func fail(_ id: UUID) {
        let waiter = lock.withLock { waiters.removeValue(forKey: id) }
        waiter?.resume(throwing: CancellationError())
    }
}

@Suite("Session lifecycle")
struct SessionLifecycleTests {
    let central = PendingCentral()
    let stores: Stores

    init() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xgrc-lifecycle-\(UUID().uuidString)", isDirectory: true)
        stores = Stores(directory: directory, secrets: InMemorySecretStore())
    }

    private func coordinator(minute: Duration = .seconds(60), demo: FakeCamera = FakeCamera(behavior: .instant),
                             demoLocation: any LocationSource = SimulatedLocationSource(interval: .milliseconds(20)))
        -> SessionCoordinator {
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(), os: "test", device: "test",
                                                               appVersion: "0"))
        return SessionCoordinator(stores: stores, central: central, demoCentral: DemoCentral(camera: demo),
                                  location: SimulatedLocationSource(interval: .milliseconds(20)),
                                  demoLocation: demoLocation,
                                  autoDisconnectUnit: minute, autoDisconnectCheck: .milliseconds(10), logger: logger)
    }

    private func sony(_ name: String = "a7 IV") -> CameraRecord {
        CameraRecord(driverID: SonyDriver.descriptor.id, name: name, modelCode: nil, peripheralID: UUID())
    }

    private func snapshot(_ coordinator: SessionCoordinator) async -> SessionSnapshot? {
        var iterator = coordinator.sessionSnapshots().makeAsyncIterator()
        return await iterator.next()
    }

    @Test("Ending a session whose camera never answered cancels the pending connect")
    func endCancelsActivation() async throws {
        let coordinator = coordinator()
        let record = sony()
        let activation = Task { try await coordinator.activate(record) }
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        #expect(await snapshot(coordinator)?.link == .connecting)

        await coordinator.endSession()
        await #expect(throws: CancellationError.self) { try await activation.value }
        #expect(central.pending.isEmpty)
        #expect(await snapshot(coordinator)?.camera == nil)
    }

    @Test("A camera that stays off is ended by the unreachable auto disconnect")
    func unreachableWhileConnecting() async throws {
        try await stores.settings.update { $0.autoDisconnectMinutes = 5 }
        let coordinator = coordinator(minute: .milliseconds(40))
        let record = sony()
        let activation = Task { try await coordinator.activate(record) }
        #expect(await eventually { await snapshot(coordinator)?.ended == .unreachable(minutes: 5) })
        await #expect(throws: CancellationError.self) { try await activation.value }
        #expect(central.pending.isEmpty)
    }

    @Test("Switching cameras while the first is still connecting leaves one session")
    func secondActivationWins() async throws {
        let coordinator = coordinator()
        let first = sony("first")
        let second = sony("second")
        let firstCamera = FakeCamera(behavior: .instant)
        let secondCamera = FakeCamera(behavior: .instant)
        central.setTransport(firstCamera, for: first.peripheralID)
        central.setTransport(secondCamera, for: second.peripheralID)

        let one = Task { try await coordinator.activate(first) }
        #expect(await eventually { central.pending.contains(first.peripheralID) })
        let two = Task { try await coordinator.activate(second) }
        await #expect(throws: CancellationError.self) { try await one.value }
        #expect(await eventually { central.pending.contains(second.peripheralID) })
        // The first camera comes into range late: nothing installs it.
        central.complete(first.peripheralID)
        central.complete(second.peripheralID)
        try await two.value
        #expect(await coordinator.activeCamera()?.id == second.id)
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })
        #expect(await firstCamera.received.isEmpty)
        await coordinator.endSession()
    }

    @Test("With Auto reconnect off, a dropped link ends the session")
    func autoReconnectOff() async throws {
        try await stores.settings.update { $0.autoReconnect = false }
        let coordinator = coordinator()
        let record = sony()
        let camera = FakeCamera(behavior: .instant)
        central.setTransport(camera, for: record.peripheralID)
        let activation = Task { try await coordinator.activate(record) }
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        central.complete(record.peripheralID)
        try await activation.value
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })

        await camera.dropLink()
        #expect(await eventually { await snapshot(coordinator)?.ended == .linkLost })
        #expect(await coordinator.activeCamera() == nil)
        #expect(await stores.settings.load().lastActiveCameraID == nil)
    }

    @Test("With Auto reconnect on, a dropped link reconnects and the session carries on")
    func autoReconnectOn() async throws {
        let coordinator = coordinator()
        let record = sony()
        let camera = FakeCamera(behavior: .instant)
        central.setTransport(camera, for: record.peripheralID)
        let activation = Task { try await coordinator.activate(record) }
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        central.complete(record.peripheralID)
        try await activation.value
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })

        await camera.dropLink()
        #expect(await eventually { await snapshot(coordinator)?.link == .reconnecting })
        await camera.restoreLink()
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })
        #expect(await coordinator.activeCamera()?.id == record.id)
        await coordinator.endSession()
    }

    @Test("Forgetting a camera that is still connecting cancels its connect")
    func forgetWhileConnecting() async throws {
        let coordinator = coordinator()
        let record = sony()
        try await stores.cameras.update { $0 = [record] }
        let activation = Task { try await coordinator.activate(record) }
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        try await coordinator.forget(record)
        await #expect(throws: CancellationError.self) { try await activation.value }
        #expect(central.pending.isEmpty)
        #expect(await coordinator.cameras().isEmpty)
    }

    @Test("A restored connection no session uses is released at launch")
    func releaseRestored() async throws {
        let stray = UUID()
        central.restored = [stray]
        #expect(await coordinator().restoreSession() == false)
        #expect(central.cancelled.contains(stray))
    }

    @Test("A link that drops with no OS reconnect pending is connected again by the session")
    func reconnectAfterPlainDrop() async throws {
        let coordinator = coordinator()
        let record = sony()
        let camera = FakeCamera(behavior: .instant)
        central.setTransport(camera, for: record.peripheralID)
        let activation = Task { try await coordinator.activate(record) }
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        central.complete(record.peripheralID)
        try await activation.value
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })

        // As a link without auto reconnect drops: the session queues its own connect.
        await camera.dropLink(isReconnecting: false)
        #expect(await eventually { await snapshot(coordinator)?.link == .reconnecting })
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        await camera.connectLink()
        central.complete(record.peripheralID)
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })
        await coordinator.endSession()
    }

    @Test("A session ended while it reconnects stays ended: the reconnect is cancelled and nothing reopens at launch")
    func endWhileReconnecting() async throws {
        let coordinator = coordinator()
        let record = sony()
        try await stores.cameras.update { $0 = [record] }
        let camera = FakeCamera(behavior: .instant)
        central.setTransport(camera, for: record.peripheralID)
        let activation = Task { try await coordinator.activate(record) }
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        central.complete(record.peripheralID)
        try await activation.value
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })
        #expect(await stores.settings.load().lastActiveCameraID == record.id)

        await camera.dropLink()
        #expect(await eventually { await snapshot(coordinator)?.link == .reconnecting })
        await coordinator.endSession()
        #expect(central.cancelled.contains(record.peripheralID))
        #expect(await stores.settings.load().lastActiveCameraID == nil)

        // The camera comes back: the ended session does not.
        await camera.restoreLink()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await coordinator.activeCamera() == nil)
        #expect(await snapshot(coordinator)?.camera == nil)

        let relaunched = self.coordinator()
        #expect(await relaunched.restoreSession() == false)
        #expect(central.pending.isEmpty)
    }

    @Test("The last session reopens at launch with Auto reconnect on, and is dropped with it off")
    func restoreAtLaunch() async throws {
        let record = sony()
        try await stores.cameras.update { $0 = [record] }
        try await stores.settings.update { $0.lastActiveCameraID = record.id }
        let camera = FakeCamera(behavior: .instant)
        central.setTransport(camera, for: record.peripheralID)

        let relaunched = coordinator()
        let restore = Task { await relaunched.restoreSession() }
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        central.complete(record.peripheralID)
        #expect(await restore.value)
        #expect(await relaunched.activeCamera()?.id == record.id)
        #expect(await relaunched.isGeotagging() == false, "geotagging was not on")
        await relaunched.endSession()

        try await stores.settings.update {
            $0.lastActiveCameraID = record.id
            $0.autoReconnect = false
        }
        let off = coordinator()
        #expect(await off.restoreSession() == false)
        #expect(await stores.settings.load().lastActiveCameraID == nil)
        #expect(central.pending.isEmpty)
    }

    @Test("Geotag only starts geotagging when the link becomes ready later")
    func geotagOnlyWhenReadyLater() async throws {
        let coordinator = coordinator()
        try await coordinator.setMode(.geotagOnly)
        let record = sony()
        let camera = FakeCamera(behavior: .instant)
        await camera.dropLink()
        central.setTransport(camera, for: record.peripheralID)
        let activation = Task { try await coordinator.activate(record) }
        #expect(await eventually { central.pending.contains(record.peripheralID) })
        central.complete(record.peripheralID)
        try await activation.value
        #expect(await coordinator.isGeotagging() == false)

        await camera.restoreLink()
        #expect(await eventually { await camera.locationPackets().count >= 1 })
        #expect(await coordinator.isGeotagging())
        await coordinator.endSession()
        #expect(await camera.locationLock == 0)
    }

    @Test("Two geotag starts at once make one stream, and stop ends it")
    func concurrentGeotagStarts() async throws {
        let camera = FakeCamera(behavior: .instant)
        let coordinator = coordinator(demo: camera)
        try await stores.settings.update { $0.showDemoCamera = true }
        let record = CameraRecord(driverID: SonyDriver.descriptor.id, name: "Demo", modelCode: nil,
                                  peripheralID: DemoCentral.peripheralID, isDemo: true)
        try await coordinator.activate(record)
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })
        async let a = coordinator.startGeotag()
        async let b = coordinator.startGeotag()
        _ = await (a, b)
        #expect(await eventually { await camera.locationPackets().count >= 1 })
        await coordinator.stopGeotag()
        #expect(await camera.locationLock == 0)
        let stopped = await camera.locationPackets().count
        try await Task.sleep(for: .milliseconds(200))
        #expect(await camera.locationPackets().count == stopped, "no second streamer keeps pushing")
        await coordinator.endSession()
    }

    @Test("AF hold on a camera that never confirms focus does not block idle auto disconnect")
    func afHoldDoesNotBlockIdle() async throws {
        try await stores.settings.update {
            $0.autoDisconnectMinutes = 5
            $0.afHold = true
            $0.showDemoCamera = true
        }
        let camera = FakeCamera(behavior: FakeCamera.Behavior(focusAckDelay: nil, shutterAckDelay: .zero))
        let coordinator = coordinator(minute: .milliseconds(40), demo: camera)
        let record = CameraRecord(driverID: SonyDriver.descriptor.id, name: "Demo", modelCode: nil,
                                  peripheralID: DemoCentral.peripheralID, isDemo: true)
        try await coordinator.activate(record)
        await coordinator.shutter(.focus)
        #expect(await eventually { await snapshot(coordinator)?.ended == .idle(minutes: 5) })
        // Ending released the half-press.
        #expect(await camera.commands().map(\.hexString).suffix(2) == ["01 08", "01 06"])
    }

    @Test("Shoot from an intent says when it closed a bulb or cancelled a countdown")
    func intentReportsWhatHappened() async throws {
        try await stores.settings.update {
            $0.showDemoCamera = true
            $0.bulbSeconds = 30
        }
        let camera = FakeCamera(behavior: .instant)
        let coordinator = coordinator(demo: camera)
        let record = CameraRecord(driverID: SonyDriver.descriptor.id, name: "Demo", modelCode: nil,
                                  peripheralID: DemoCentral.peripheralID, isDemo: true)
        try await coordinator.activate(record)
        #expect(await eventually { await snapshot(coordinator)?.link == .ready })
        _ = await coordinator.startGeotag()
        await coordinator.settingsChanged()

        #expect(try await coordinator.shootFromIntent() == .bulb(seconds: 30, delay: 0))
        #expect(await eventually {
            var iterator = coordinator.shutterSnapshots().makeAsyncIterator()
            if case .bulbOpen = await iterator.next()?.phase { return true }
            return false
        })
        #expect(try await coordinator.shootFromIntent() == .bulbClosed)

        try await stores.settings.update {
            $0.bulbSeconds = 0
            $0.releaseDelaySeconds = 30
        }
        await coordinator.settingsChanged()
        #expect(await eventually {
            var iterator = coordinator.shutterSnapshots().makeAsyncIterator()
            if case .bulbOpen = await iterator.next()?.phase { return false }
            return true
        })
        #expect(try await coordinator.shootFromIntent() == .countdown(seconds: 30))
        #expect(try await coordinator.shootFromIntent() == .countdownCancelled)
        await coordinator.endSession()
    }
}

@Suite("Broadcaster")
struct BroadcasterTests {
    @Test("Every subscriber sees values in the order they were yielded")
    func ordering() async {
        let broadcaster = Broadcaster<Int>(replayLast: true)
        broadcaster.yield(0)
        let stream = broadcaster.stream()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for i in 1...200 { broadcaster.yield(i) } ; broadcaster.finish() }
        }
        var last = -1
        for await value in stream {
            #expect(value > last)
            last = value
        }
        #expect(last == 200)
    }
}
