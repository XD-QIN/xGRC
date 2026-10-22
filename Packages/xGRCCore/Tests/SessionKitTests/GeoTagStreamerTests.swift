import BLEKit
import CameraKit
import Foundation
import LocationKit
@testable import SessionKit
import Testing

/// Geotag defaults (architecture doc § Geotag defaults) against the real `SonyDriver`
/// on a `FakeCamera`, on a manual clock.
@Suite("GeoTagStreamer on Sony")
struct GeoTagStreamerTests {
    let clock = ManualClock()
    let base = Date(timeIntervalSince1970: 1_792_069_509)
    let camera: FakeCamera
    let driver: SonyDriver
    let source = SimulatedLocationSource(interval: nil)

    init() async throws {
        camera = FakeCamera(behavior: .instant)
        driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
    }

    private func now() -> Date {
        base.addingTimeInterval(clock.now.offset.inSeconds)
    }

    private func streamer(_ configure: (inout GeotagConfiguration) -> Void = { _ in },
                          source: (any LocationSource)? = nil) -> GeoTagStreamer<ManualClock> {
        var configuration = GeotagConfiguration()
        configure(&configuration)
        let clock = self.clock
        let base = self.base
        return GeoTagStreamer(driver: driver, source: source ?? self.source, clock: clock,
                              configuration: configuration,
                              now: { base.addingTimeInterval(clock.now.offset.inSeconds) })
    }

    private func fix(north metres: Double = 0, accuracy: Double = 5, age: TimeInterval = 0) -> GeoFix {
        GeoFix(latitude: 35.658581 + metres / 111_195, longitude: 139.745433, altitude: 42,
               horizontalAccuracy: accuracy, timestamp: now().addingTimeInterval(-age))
    }

    private func packets() async -> Int {
        await camera.locationPackets().count
    }

    @Test("The first valid fix is pushed at once, then one push per interval")
    func interval() async throws {
        let streamer = streamer()
        #expect(await streamer.start() == .waitingForFix)
        await source.emit(fix())
        await settle()
        #expect(await packets() == 1)
        #expect(await streamer.currentSnapshot().status == .tagging)

        // Fresh fixes keep arriving each second; pushes stay on the 5 s interval.
        for _ in 0..<5 {
            await clock.advance(by: .seconds(1))
            await source.emit(fix())
            await settle()
        }
        #expect(await packets() == 2)
        await streamer.stop()
    }

    @Test("Fixes worse than 50 m are never sent")
    func accuracyGate() async throws {
        let streamer = streamer()
        await streamer.start()
        await source.emit(fix(accuracy: 80))
        await settle()
        await clock.advance(by: .seconds(5))
        #expect(await packets() == 0)
        await streamer.stop()
    }

    @Test("Sony never gets a fix older than 10 s")
    func fixAge() async throws {
        let streamer = streamer()
        await streamer.start()
        await source.emit(fix(age: 12))
        await settle()
        #expect(await packets() == 0)

        await source.emit(fix())
        await settle()
        #expect(await packets() == 1)
        // No new fixes: the one we have expires before the second tick.
        await clock.advance(by: .seconds(5))
        await clock.advance(by: .seconds(6))
        #expect(await packets() == 2)
        await clock.advance(by: .seconds(5))
        #expect(await packets() == 2)
        await streamer.stop()
    }

    @Test("Moving more than 10 m beyond the fix's accuracy pushes at once")
    func movement() async throws {
        let streamer = streamer()
        await streamer.start()
        await source.emit(fix())
        await settle()
        await clock.advance(by: .seconds(1))
        await source.emit(fix(north: 8))
        await settle()
        #expect(await packets() == 1)
        await clock.advance(by: .seconds(1))
        await source.emit(fix(north: 20))
        await settle()
        #expect(await packets() == 2)
        await streamer.stop()
    }

    @Test("No valid fix for 30 s turns the page amber")
    func noFix() async throws {
        let streamer = streamer()
        await streamer.start()
        for _ in 0..<6 { await clock.advance(by: .seconds(5)) }
        #expect(await streamer.currentSnapshot().status == .noFix)
        await source.emit(fix())
        await settle()
        #expect(await streamer.currentSnapshot().status == .tagging)
        await streamer.stop()
    }

    @Test("Pushes pause while the link is down and resume on reconnect")
    func linkLoss() async throws {
        let streamer = streamer()
        await streamer.start()
        await source.emit(fix())
        await settle()
        await streamer.linkLost()
        #expect(await streamer.currentSnapshot().status == .paused)
        await source.emit(fix())
        await clock.advance(by: .seconds(5))
        #expect(await packets() == 1)

        await source.emit(fix())
        await settle()
        await streamer.linkRestored()
        #expect(await packets() == 2)
        #expect(await streamer.currentSnapshot().status == .tagging)
        await streamer.stop()
    }

    @Test("A location link the reconnect could not enable shows as not tagging, and is enabled again")
    func relinkAfterFailedReconnect() async throws {
        let streamer = streamer()
        await streamer.start()
        await source.emit(fix())
        await settle()
        #expect(await packets() == 1)

        // The camera was off for a while, and another phone took its
        // location lock meanwhile.
        var behavior = await camera.behavior
        behavior.locationLockedElsewhere = true
        await camera.setBehavior(behavior)
        await camera.dropLink()
        await streamer.linkLost()
        await camera.powerCycle()
        await camera.restoreLink()
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await streamer.linkRestored()
        for _ in 0..<2 {
            await source.emit(fix())
            await clock.advance(by: .seconds(5))
        }
        #expect(await streamer.currentSnapshot().status == .cameraNotTagging)
        #expect(await packets() == 1)

        // The other phone let go: within the relink interval pushes go through again.
        behavior.locationLockedElsewhere = false
        await camera.setBehavior(behavior)
        for _ in 0..<7 {
            await source.emit(fix())
            await clock.advance(by: .seconds(5))
        }
        #expect(await packets() > 1)
        #expect(await streamer.currentSnapshot().status == .tagging)
        await streamer.stop()
    }

    @Test("Refused location permission fails without touching the camera")
    func denied() async throws {
        let refused = SimulatedLocationSource(interval: nil, authorization: .denied)
        let streamer = streamer(source: refused)
        #expect(await streamer.start() == .failed(.locationDenied))
        #expect(await camera.locationLock == 0)
    }

    @Test("The camera's location setting off is reported, not retried")
    func cameraSettingOff() async throws {
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .zero, locationLinkOff: true))
        let streamer = streamer()
        #expect(await streamer.start() == .failed(.cameraSettingOff))
    }

    @Test("Keep camera awake writes CC02 every 9 s, and only when on")
    func keepAlive() async throws {
        let camera = self.camera
        let clock = self.clock
        let keepAlives = { @Sendable in
            await camera.received.filter { $0.characteristic == Sony.cc02 }.map(\.data.hexString)
        }
        // Both loops (push and keep-alive) must be asleep before time moves.
        let bothAsleep = { @Sendable in await eventually { clock.sleeperCount == 2 } }

        let off = streamer()
        await off.start()
        #expect(await bothAsleep())
        await clock.advance(by: .seconds(9))
        #expect(await bothAsleep())
        await clock.advance(by: .seconds(9))
        #expect(await keepAlives().isEmpty)
        await off.stop()

        let on = streamer { $0.keepAwake = true }
        await on.start()
        #expect(await bothAsleep())
        await clock.advance(by: .seconds(9))
        #expect(await eventually { await keepAlives().count == 1 })
        #expect(await bothAsleep())
        await clock.advance(by: .seconds(9))
        #expect(await eventually { await keepAlives() == ["03 08 10 00", "03 08 10 00"] })
        await on.stop()
    }

    @Test("Stop releases the camera's location lock")
    func stopReleases() async throws {
        let streamer = streamer()
        await streamer.start()
        #expect(await camera.locationLock == 1)
        await streamer.stop()
        #expect(await camera.locationLock == 0)
        #expect(await streamer.currentSnapshot().status == .off)
    }
}

@Suite("Fix filter")
struct FixFilterTests {
    let now = Date(timeIntervalSince1970: 1_792_069_509)

    private func fix(_ accuracy: Double, age: TimeInterval = 0) -> GeoFix {
        GeoFix(latitude: 1, longitude: 2, horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(-age))
    }

    @Test("A recent good fix is not replaced by one more than 3× worse")
    func worseFix() {
        var filter = FixFilter()
        let first = filter.offer(fix(5), now: now)
        let fourTimesWorse = filter.offer(fix(20), now: now)
        let threeTimesWorse = filter.offer(fix(15), now: now)
        #expect(first && !fourTimesWorse && threeTimesWorse)
        #expect(filter.current(now: now)?.horizontalAccuracy == 15)
    }

    @Test("Once the good fix is stale, a worse one is accepted")
    func staleBest() {
        var filter = FixFilter(maximumAge: .seconds(10))
        let first = filter.offer(fix(5, age: 0), now: now)
        let later = now.addingTimeInterval(11)
        #expect(first && filter.current(now: later) == nil)
        let worse = filter.offer(GeoFix(latitude: 1, longitude: 2, horizontalAccuracy: 40, timestamp: later), now: later)
        #expect(worse)
    }

    @Test("Pushes keep a fixed schedule; ticks missed by a slow push are skipped")
    func schedule() {
        typealias Streamer = GeoTagStreamer<ManualClock>
        let start = ManualClock.Instant(offset: .zero)
        let first = Streamer.nextTick(after: start, every: .seconds(5), now: start.advanced(by: .seconds(1)))
        #expect(first.offset == .seconds(5))
        // The loop reached its sleep late: the deadline is still on the schedule.
        let late = Streamer.nextTick(after: first, every: .seconds(5), now: first.advanced(by: .seconds(3)))
        #expect(late.offset == .seconds(10))
        // A push that took 12 s skips the ticks it missed.
        let slow = Streamer.nextTick(after: late, every: .seconds(5), now: late.advanced(by: .seconds(12)))
        #expect(slow.offset == .seconds(25))
        #expect(Streamer.nextTick(after: start, every: .zero, now: start) == start)
    }
}
