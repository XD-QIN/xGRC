import BLEKit
import CameraKit
import Foundation
import LocationKit
import Persistence
@testable import SessionKit
import SharedState
import Testing

/// End to end on the demo camera: scan, pair, shoot, reconnect, end, forget.
@Suite("SessionCoordinator on the demo camera")
struct SessionCoordinatorTests {
    let camera = FakeCamera(behavior: .instant)
    let coordinator: SessionCoordinator
    let stores: Stores

    init() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xgrc-tests-\(UUID().uuidString)", isDirectory: true)
        stores = Stores(directory: directory, secrets: InMemorySecretStore())
        try await stores.settings.update { $0.showDemoCamera = true }
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(), os: "test", device: "test",
                                                               appVersion: "0"))
        coordinator = SessionCoordinator(stores: stores, central: DemoCentral(camera: FakeCamera()),
                                         demoCentral: DemoCentral(camera: camera), logger: logger)
    }

    private func firstDemoCamera() async -> DiscoveredCamera? {
        for await found in await coordinator.scan() where found.isDemo {
            return found
        }
        return nil
    }

    private func link() async -> LinkState? {
        var iterator = coordinator.sessionSnapshots().makeAsyncIterator()
        return await iterator.next()?.link
    }

    @Test("Pair, shoot, end")
    func pairAndShoot() async throws {
        let found = try #require(await firstDemoCamera())
        #expect(found.match.isPairable)
        let record = try await coordinator.pair(found) { _ in }
        #expect(await coordinator.cameras().map(\.id) == [record.id])
        #expect(await eventually { await link() == .ready })

        await coordinator.shutter(.shoot)
        #expect(await eventually {
            var iterator = coordinator.shutterSnapshots().makeAsyncIterator()
            return await iterator.next()?.confirmed == 1
        })
        #expect(await camera.commands().map(\.hexString) == ["01 07", "01 09", "01 08", "01 06"])

        await coordinator.endSession()
        #expect(await coordinator.activeCamera() == nil)
        #expect(await camera.isLinkUp == false)
    }

    @Test("A reconnect re-registers and releases every button first")
    func reconnect() async throws {
        let found = try #require(await firstDemoCamera())
        _ = try await coordinator.pair(found) { _ in }
        #expect(await eventually { await link() == .ready })

        await camera.dropLink()
        #expect(await eventually { await link() == .reconnecting })
        await camera.clearReceived()
        await camera.restoreLink()
        #expect(await eventually { await link() == .ready })
        #expect(await eventually { await camera.commands().map(\.hexString) == ["01 08", "01 06"] })
        await coordinator.endSession()
    }

    @Test("Activating a saved camera connects without re-pairing")
    func activateSaved() async throws {
        let found = try #require(await firstDemoCamera())
        let record = try await coordinator.pair(found) { _ in }
        await coordinator.endSession()
        await camera.clearReceived()

        try await coordinator.activate(record)
        #expect(await eventually { await link() == .ready })
        #expect(await camera.received.contains { $0.characteristic == Sony.ee01 } == false)
        await coordinator.endSession()
    }

    @Test("Forget removes the record and its identity")
    func forget() async throws {
        let found = try #require(await firstDemoCamera())
        let record = try await coordinator.pair(found) { _ in }
        try await coordinator.forget(record)
        #expect(await coordinator.cameras().isEmpty)
        #expect(try IdentityStore(secrets: stores.secrets).cameraIdentity(for: record.id) == nil)
    }

    @Test("Geotag on the demo camera pushes fixes; the session record stays open until stopped")
    func geotag() async throws {
        let walk = SimulatedLocationSource(interval: .milliseconds(20))
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(), os: "test", device: "test",
                                                               appVersion: "0"))
        let coordinator = SessionCoordinator(stores: stores, central: DemoCentral(camera: FakeCamera()),
                                             demoCentral: DemoCentral(camera: camera), demoLocation: walk,
                                             logger: logger)
        var found: DiscoveredCamera?
        for await camera in await coordinator.scan() where camera.isDemo {
            found = camera
            break
        }
        let record = try await coordinator.pair(try #require(found)) { _ in }

        let status = await coordinator.startGeotag()
        #expect(status == .waitingForFix || status == .tagging)
        #expect(await stores.settings.load().openGeotagSession)
        #expect(await eventually { await camera.locationPackets().count >= 1 })
        #expect(await eventually {
            var iterator = coordinator.geotagSnapshots().makeAsyncIterator()
            return await iterator.next()?.pushes ?? 0 >= 1
        })

        // Launch after a relaunch by Core Location: the open session comes back.
        await coordinator.stopGeotag()
        #expect(await camera.locationLock == 0)
        #expect(await stores.settings.load().openGeotagSession == false)
        _ = await coordinator.startGeotag()
        #expect(await stores.settings.load().lastActiveCameraID == record.id)

        await coordinator.endSession()
        #expect(await stores.settings.load().openGeotagSession == false)
        #expect(await camera.locationLock == 0)
    }

    @Test("A session's accepted fixes are recorded to its GPS track, which ends with the session")
    func gpsTrack() async throws {
        let walk = SimulatedLocationSource(interval: .milliseconds(20))
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(), os: "test", device: "test",
                                                               appVersion: "0"))
        let coordinator = SessionCoordinator(stores: stores, central: DemoCentral(camera: FakeCamera()),
                                             demoCentral: DemoCentral(camera: camera), demoLocation: walk,
                                             logger: logger)
        var found: DiscoveredCamera?
        for await camera in await coordinator.scan() where camera.isDemo {
            found = camera
            break
        }
        _ = try await coordinator.pair(try #require(found)) { _ in }
        #expect(await stores.tracks.list().isEmpty)

        _ = await coordinator.startGeotag()
        #expect(await eventually {
            guard let track = await stores.tracks.list().first else { return false }
            return (try? await stores.tracks.points(of: track).count) ?? 0 >= 3
        })
        // A shot marks the track at the last fix.
        await coordinator.shutter(.shoot)
        #expect(await eventually {
            guard let track = await stores.tracks.list().first else { return false }
            return (try? await stores.tracks.points(of: track).filter(\.isShot).count) == 1
        })
        await coordinator.endSession()
        let track = try #require(await stores.tracks.list().first)
        let recorded = try await stores.tracks.points(of: track).count
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await stores.tracks.points(of: track).count == recorded)
        #expect(await stores.tracks.list().count == 1)
    }

    @Test("An open geotag session is restored at launch")
    func restore() async throws {
        let found = try #require(await firstDemoCamera())
        let record = try await coordinator.pair(found) { _ in }
        _ = await coordinator.startGeotag()
        // Simulate termination: drop the in-memory session but keep the stores.
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(), os: "test", device: "test",
                                                               appVersion: "0"))
        let relaunched = SessionCoordinator(stores: stores, central: DemoCentral(camera: FakeCamera()),
                                            demoCentral: DemoCentral(camera: camera),
                                            demoLocation: SimulatedLocationSource(interval: .milliseconds(20)),
                                            logger: logger)
        #expect(await relaunched.restoreSession())
        #expect(await relaunched.activeCamera()?.id == record.id)
        #expect(await relaunched.isGeotagging())
        await relaunched.endSession()
    }

    // MARK: Modes

    private func walkingCoordinator() -> SessionCoordinator {
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(), os: "test", device: "test",
                                                               appVersion: "0"))
        return SessionCoordinator(stores: stores, central: DemoCentral(camera: FakeCamera()),
                                  demoCentral: DemoCentral(camera: camera),
                                  demoLocation: SimulatedLocationSource(interval: .milliseconds(20)),
                                  logger: logger)
    }

    private func demo(_ coordinator: SessionCoordinator) async -> DiscoveredCamera? {
        for await found in await coordinator.scan() where found.isDemo { return found }
        return nil
    }

    @Test("Geotag only: geotagging starts with the session and the shutter does nothing")
    func geotagOnly() async throws {
        let coordinator = walkingCoordinator()
        try await coordinator.setMode(.geotagOnly)
        // The camera's Bluetooth Rmt Ctrl may be off in this mode.
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .zero,
                                                     remoteControlOff: true))
        _ = try await coordinator.pair(try #require(await demo(coordinator))) { _ in }
        #expect(await eventually { await camera.locationPackets().count >= 1 })
        await coordinator.shutter(.shoot)
        await settle()
        #expect(await camera.commands().contains(Data([0x01, 0x09])) == false)
        await coordinator.endSession()
    }

    @Test("Remote only: geotag cannot start, and switching to it stops a running stream")
    func remoteOnly() async throws {
        let coordinator = walkingCoordinator()
        _ = try await coordinator.pair(try #require(await demo(coordinator))) { _ in }
        #expect(await eventually { await link(of: coordinator) == .ready })
        _ = await coordinator.startGeotag()
        #expect(await eventually { await camera.locationLock == 1 })

        try await coordinator.setMode(.remoteOnly)
        #expect(await camera.locationLock == 0)
        guard case .failed = await coordinator.startGeotag() else {
            Issue.record("geotag started in Remote only")
            return
        }
        await coordinator.shutter(.shoot)
        #expect(await eventually { await camera.commands().contains(Data([0x01, 0x09])) })
        await coordinator.endSession()
    }

    @Test("The mode is remembered on the device")
    func modePersists() async throws {
        try await coordinator.setMode(.geotagOnly)
        let reloaded = Stores(directory: await stores.settings.url.deletingLastPathComponent(),
                              secrets: InMemorySecretStore())
        #expect(await reloaded.settings.load().sessionMode == .geotagOnly)
    }

    // MARK: Intents

    @Test("Shoot from an intent focuses, fires and reports the camera's ack")
    func intentShoot() async throws {
        await #expect(throws: SessionError.noActiveSession) { try await coordinator.shootFromIntent() }
        _ = try await coordinator.pair(try #require(await firstDemoCamera())) { _ in }
        #expect(await eventually { await link() == .ready })
        guard case .result(let result) = try await coordinator.shootFromIntent() else {
            Issue.record("expected a result")
            return
        }
        #expect(result.isConfirmed)
        #expect(await camera.commands().map(\.hexString) == ["01 07", "01 09", "01 08", "01 06"])
        await coordinator.endSession()
    }

    @Test("Shoot from an intent counts down only while geotagging, and is refused in Geotag only")
    func intentReleaseDelay() async throws {
        let coordinator = walkingCoordinator()
        try await stores.settings.update { $0.releaseDelaySeconds = 30 }
        _ = try await coordinator.pair(try #require(await demo(coordinator))) { _ in }
        #expect(await eventually { await link(of: coordinator) == .ready })

        // Not geotagging: the app may be suspended before a countdown ends, so it fires at once.
        guard case .result = try await coordinator.shootFromIntent() else {
            Issue.record("expected an immediate shot")
            return
        }
        _ = await coordinator.startGeotag()
        #expect(try await coordinator.shootFromIntent() == .countdown(seconds: 30))
        await coordinator.shutter(.cancel)

        try await coordinator.setMode(.geotagOnly)
        await #expect(throws: SessionError.notInMode(.geotagOnly)) { try await coordinator.shootFromIntent() }
        await coordinator.endSession()
    }

    @Test("Shoot from an intent with a bulb time on Sony is refused unless geotagging keeps the app running")
    func intentBulbNeedsApp() async throws {
        try await stores.settings.update { $0.bulbSeconds = 60 }
        _ = try await coordinator.pair(try #require(await firstDemoCamera())) { _ in }
        #expect(await eventually { await link() == .ready })
        // In BULB a lone press opens a shutter nothing would close.
        await #expect(throws: SessionError.bulbNeedsApp) { try await coordinator.shootFromIntent() }
        #expect(!(await camera.commands().map(\.hexString)).contains("01 09"))
        await coordinator.endSession()
    }

    @Test("A shot slower than the intent's time limit is reported as still running")
    func intentTimeout() async throws {
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .seconds(1)))
        _ = try await coordinator.pair(try #require(await firstDemoCamera())) { _ in }
        #expect(await eventually { await link() == .ready })
        #expect(try await coordinator.shootFromIntent(timeout: .milliseconds(100)) == .stillRunning)
        await coordinator.endSession()
    }

    // MARK: Auto disconnect

    /// One auto-disconnect "minute" is 40 ms here.
    private func quickCoordinator() -> SessionCoordinator {
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(), os: "test", device: "test",
                                                               appVersion: "0"))
        return SessionCoordinator(stores: stores, central: DemoCentral(camera: FakeCamera()),
                                  demoCentral: DemoCentral(camera: camera),
                                  demoLocation: SimulatedLocationSource(interval: .milliseconds(20)),
                                  autoDisconnectUnit: .milliseconds(40), autoDisconnectCheck: .milliseconds(10),
                                  logger: logger)
    }

    private func ended(_ coordinator: SessionCoordinator) async -> SessionEndReason? {
        var iterator = coordinator.sessionSnapshots().makeAsyncIterator()
        return await iterator.next()?.ended
    }

    @Test("Auto disconnect ends an idle session and frees the camera")
    func autoDisconnectIdle() async throws {
        try await stores.settings.update { $0.autoDisconnectMinutes = 5 }
        let coordinator = quickCoordinator()
        _ = try await coordinator.pair(try #require(await demo(coordinator))) { _ in }
        #expect(await eventually { await ended(coordinator) == .idle(minutes: 5) })
        #expect(await coordinator.activeCamera() == nil)
        #expect(await camera.isLinkUp == false)
    }

    @Test("Geotagging counts as activity; idle time starts when it stops")
    func autoDisconnectGeotag() async throws {
        try await stores.settings.update { $0.autoDisconnectMinutes = 5 }
        let coordinator = quickCoordinator()
        _ = try await coordinator.pair(try #require(await demo(coordinator))) { _ in }
        _ = await coordinator.startGeotag()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await coordinator.activeCamera() != nil)
        await coordinator.stopGeotag()
        #expect(await eventually { await ended(coordinator) == .idle(minutes: 5) })
    }

    @Test("Auto disconnect ends a session that cannot reach the camera, even while geotagging")
    func autoDisconnectUnreachable() async throws {
        try await stores.settings.update { $0.autoDisconnectMinutes = 5 }
        let coordinator = quickCoordinator()
        _ = try await coordinator.pair(try #require(await demo(coordinator))) { _ in }
        _ = await coordinator.startGeotag()
        await camera.dropLink()
        #expect(await eventually { await ended(coordinator) == .unreachable(minutes: 5) })
        #expect(await stores.settings.load().openGeotagSession == false)
    }

    @Test("Auto disconnect off keeps the session")
    func autoDisconnectOff() async throws {
        try await stores.settings.update { $0.autoDisconnectMinutes = 0 }
        let coordinator = quickCoordinator()
        _ = try await coordinator.pair(try #require(await demo(coordinator))) { _ in }
        try await Task.sleep(for: .milliseconds(400))
        #expect(await coordinator.activeCamera() != nil)
        await coordinator.endSession()
    }

    @Test("Auto disconnect policy")
    func autoDisconnectPolicy() {
        let t0 = ContinuousClock.now
        var policy = AutoDisconnect(minutes: 15, now: t0)
        policy.link(.ready, now: t0)
        #expect(policy.check(now: t0 + .seconds(14 * 60), busy: false) == nil)
        policy.activity(now: t0 + .seconds(10 * 60))
        #expect(policy.check(now: t0 + .seconds(24 * 60), busy: false) == nil)
        #expect(policy.check(now: t0 + .seconds(25 * 60), busy: false) == .idle(minutes: 15))
        // Busy work moves the idle start to when it ends.
        #expect(policy.check(now: t0 + .seconds(30 * 60), busy: true) == nil)
        #expect(policy.check(now: t0 + .seconds(44 * 60), busy: false) == nil)
        // No link for 15 minutes ends it whatever is running.
        policy.link(.reconnecting, now: t0 + .seconds(40 * 60))
        #expect(policy.check(now: t0 + .seconds(54 * 60), busy: true) == nil)
        #expect(policy.check(now: t0 + .seconds(55 * 60), busy: true) == .unreachable(minutes: 15))
        #expect(AutoDisconnect(minutes: 0, now: t0).timeout == nil)
    }

    // MARK: Tile

    @Test("The tile state follows the session and ignores pushes while tagging")
    func tileState() async throws {
        var session = SessionSnapshot()
        var geotag = GeotagSnapshot()
        #expect(TileState(session: session, geotag: geotag, mode: .remoteAndGeotag) == TileState())

        session.link = .ready
        geotag.status = .tagging
        geotag.lastPushAt = Date(timeIntervalSince1970: 100)
        let tagging = TileState(session: session, geotag: geotag, mode: .geotagOnly)
        #expect(tagging.link == .connected && tagging.geotag == .tagging && !tagging.usesRemote)

        geotag.lastPushAt = Date(timeIntervalSince1970: 105)
        let pushed = TileState(session: session, geotag: geotag, mode: .geotagOnly)
        #expect(!pushed.differsVisibly(from: tagging))

        geotag.status = .paused
        let paused = TileState(session: session, geotag: geotag, mode: .geotagOnly)
        #expect(paused.differsVisibly(from: pushed))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tile-\(UUID().uuidString)")
        #expect(TileState.load(from: directory) == TileState())
        try paused.save(to: directory)
        #expect(TileState.load(from: directory) == paused)

        // Shoot needs a remote mode, a connected camera and background shooting.
        #expect(!tagging.canShoot)
        let remote = TileState(session: session, geotag: geotag, mode: .remoteAndGeotag)
        #expect(remote.canShoot)
        #expect(!TileState(session: session, geotag: geotag, mode: .remoteAndGeotag, backgroundShooting: false).canShoot)
        // A file from before `canShoot` existed still loads.
        let legacy = #"{"link":"connected","usesRemote":true,"geotag":"off"}"#
        try Data(legacy.utf8).write(to: directory.appendingPathComponent(TileState.fileName))
        #expect(TileState.load(from: directory).canShoot)
    }

    private func link(of coordinator: SessionCoordinator) async -> LinkState? {
        var iterator = coordinator.sessionSnapshots().makeAsyncIterator()
        return await iterator.next()?.link
    }
}
