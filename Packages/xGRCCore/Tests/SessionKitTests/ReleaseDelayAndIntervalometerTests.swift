import BLEKit
import CameraKit
import Foundation
import Persistence
@testable import SessionKit
import Testing

/// architecture doc § Gesture timing and precedence (release-delay rows) and
/// § Intervalometer rules, against `SonyDriver` on a `FakeCamera`.
@Suite("Release delay")
struct ReleaseDelayTests {
    let clock = ManualClock()
    let camera: FakeCamera
    let sequencer: ShotSequencer<ManualClock>

    init() async throws {
        let clock = self.clock
        camera = FakeCamera(behavior: .instant, sleep: { duration in
            try await clock.sleep(until: clock.now.advanced(by: duration), tolerance: nil)
        })
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        var configuration = SequencerConfiguration()
        configuration.releaseDelay = .seconds(5)
        sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()
    }

    private func commands() async -> [String] {
        await camera.commands().map(\.hexString)
    }

    private func input(_ inputs: ShutterInput...) async {
        for input in inputs {
            await sequencer.handle(input)
            await settle()
        }
    }

    private func phase() async -> ShutterPhase {
        await sequencer.currentSnapshot().phase
    }

    private func isCountdown(_ phase: ShutterPhase) -> Bool {
        if case .countdown = phase { return true }
        return false
    }

    @Test("Double tap starts the countdown; the shot fires at zero with focus held throughout")
    func doubleTapCountdown() async throws {
        await input(.touchDown, .touchUp, .touchDown, .touchUp)
        #expect(isCountdown(await phase()))
        #expect(await commands() == ["01 07"])

        await clock.advance(by: .seconds(4))
        #expect(await commands() == ["01 07"])
        await clock.advance(by: .seconds(1))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"])
        let snapshot = await sequencer.currentSnapshot()
        #expect(snapshot.confirmed == 1)
        #expect(snapshot.lastShotDelayed)
    }

    @Test("Shoot with nothing held counts down, then runs half-then-full itself")
    func shootCountdown() async throws {
        await input(.shoot)
        #expect(isCountdown(await phase()))
        #expect(await commands().isEmpty)
        await clock.advance(by: .seconds(5))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"])
    }

    @Test("A tap during the countdown cancels and releases every button")
    func tapCancels() async throws {
        await input(.touchDown, .touchUp, .touchDown, .touchUp)
        await clock.advance(by: .seconds(2))
        await input(.touchDown, .touchUp)
        await awaitIdle(sequencer)
        #expect(await phase() == .result(.cancelled))
        #expect(await commands() == ["01 07", "01 08", "01 06"])
        await clock.advance(by: .seconds(5))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 08", "01 06"])
        #expect(await sequencer.currentSnapshot().sent == 0)
    }

    @Test("Hand Double Tap during the countdown cancels")
    func shootCancels() async throws {
        await input(.shoot)
        await input(.shoot)
        await awaitIdle(sequencer)
        #expect(await phase() == .result(.cancelled))
        await clock.advance(by: .seconds(5))
        await awaitIdle(sequencer)
        #expect(await commands().contains("01 09") == false)
    }

    @Test("Leaving the app during the countdown cancels")
    func sceneCancels() async throws {
        await input(.shoot)
        await input(.sceneInactive)
        await awaitIdle(sequencer)
        #expect(await phase() == .result(.cancelled))
        await clock.advance(by: .seconds(5))
        #expect(await commands().contains("01 09") == false)
    }
}

@Suite("Intervalometer")
struct IntervalometerTests {
    let clock = ManualClock()
    let camera: FakeCamera
    let sequencer: ShotSequencer<ManualClock>
    let intervalometer: Intervalometer<ManualClock>

    init() async throws {
        let clock = self.clock
        camera = FakeCamera(behavior: .instant, sleep: { duration in
            try await clock.sleep(until: clock.now.advanced(by: duration), tolerance: nil)
        })
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        var configuration = SequencerConfiguration()
        // Release delay never applies to frames.
        configuration.releaseDelay = .seconds(10)
        sequencer = ShotSequencer(driver: driver, clock: clock, configuration: configuration)
        await sequencer.start()
        intervalometer = Intervalometer(sequencer: sequencer, clock: clock)
    }

    private func commands() async -> [String] {
        await camera.commands().map(\.hexString)
    }

    private func snapshot() async -> IntervalometerSnapshot {
        await intervalometer.currentSnapshot()
    }

    /// Advances one interval at a time until the run ends.
    private func runToEnd(step: Duration, limit: Int = 50) async {
        for _ in 0..<limit {
            if await !snapshot().isRunning { return }
            await clock.advance(by: step)
            // Not `idle()`: a frame waiting for a delayed ack needs the clock to move.
            await settle()
        }
    }

    @Test("Three frames, start to start, full press only, no release delay")
    func basicRun() async throws {
        await intervalometer.start(IntervalometerPlan(intervalSeconds: 2, frames: 3))
        await runToEnd(step: .seconds(2))
        let s = await snapshot()
        #expect(s.state == .finished(.completed))
        #expect(s.frame == 3 && s.sent == 3 && s.confirmed == 3)
        #expect(await commands() == ["01 09", "01 08", "01 09", "01 08", "01 09", "01 08"])
    }

    @Test("AF each frame runs the focus step on every frame")
    func focusEachFrame() async throws {
        await intervalometer.start(IntervalometerPlan(intervalSeconds: 2, frames: 2, focusEachFrame: true))
        await runToEnd(step: .seconds(2))
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06", "01 07", "01 09", "01 08", "01 06"])
    }

    @Test("Shutter-open time above 1 s runs as bulb")
    func bulbFrames() async throws {
        await intervalometer.start(IntervalometerPlan(intervalSeconds: 5, frames: 1, exposureSeconds: 3))
        await settle()
        // Open: press and release (Sony bulb toggles).
        #expect(await eventually { await commands() == ["01 09", "01 08", "01 06"] })
        // The bulb hold (the run waits for the frame, not on the clock).
        await clock.advance(by: .seconds(3), afterSleepers: 1)
        await awaitIdle(sequencer)
        // Close: a second press and release.
        #expect(await eventually {
            await commands() == ["01 09", "01 08", "01 06", "01 07", "01 09", "01 08", "01 06"]
        })
        await runToEnd(step: .seconds(1))
        #expect(await snapshot().confirmed == 1)
    }

    @Test("While the link is down frames are missed, not failed, and the run goes on")
    func missedWhileDown() async throws {
        await intervalometer.start(IntervalometerPlan(intervalSeconds: 2, frames: 4))
        await settle()
        #expect(await eventually { await snapshot().sent == 1 })
        await intervalometer.linkLost()
        await clock.advance(by: .seconds(2))
        await clock.advance(by: .seconds(2))
        #expect(await eventually { await snapshot().missed == 2 })
        await intervalometer.linkRestored()
        await runToEnd(step: .seconds(2))
        let s = await snapshot()
        #expect(s.state == .finished(.completed))
        #expect(s.sent == 2 && s.missed == 2 && s.failed == 0)
    }

    @Test("Three consecutive failures with the link up stop the run")
    func stopsOnFailures() async throws {
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .zero,
                                                     remoteControlOff: true))
        await intervalometer.start(IntervalometerPlan(intervalSeconds: 1, frames: nil))
        await runToEnd(step: .seconds(1))
        let s = await snapshot()
        #expect(s.state == .finished(.failures))
        #expect(s.failed == 3 && s.sent == 0)
    }

    @Test("A frame that overruns the interval starts the next one at once")
    func overrun() async throws {
        // The camera takes 2 s to acknowledge; the interval is 1 s.
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .seconds(2)))
        await intervalometer.start(IntervalometerPlan(intervalSeconds: 1, frames: 2))
        await runToEnd(step: .milliseconds(500))
        let s = await snapshot()
        #expect(s.state == .finished(.completed))
        #expect(s.overruns >= 1)
        #expect(s.confirmed == 2)
    }

    @Test("Initial wait delays the first frame; Stop ends the run")
    func initialWaitAndStop() async throws {
        await intervalometer.start(IntervalometerPlan(intervalSeconds: 2, frames: nil, initialWaitSeconds: 3))
        guard case .waiting = await snapshot().state else {
            Issue.record("expected waiting")
            return
        }
        await clock.advance(by: .seconds(2))
        #expect(await commands().isEmpty)
        await clock.advance(by: .seconds(1))
        #expect(await eventually { await commands() == ["01 09", "01 08"] })
        await intervalometer.stop()
        #expect(await snapshot().state == .finished(.stopped))
    }
}
