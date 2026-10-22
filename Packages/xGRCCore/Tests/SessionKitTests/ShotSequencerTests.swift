import BLEKit
import CameraKit
import Foundation
@testable import SessionKit
import Testing

/// The gesture table (architecture doc § Gesture timing and precedence) against the real
/// `SonyDriver` on a `FakeCamera`, on a manual clock.
@Suite("ShotSequencer gestures on Sony")
struct ShotSequencerTests {
    let clock = ManualClock()
    let camera: FakeCamera
    let driver: SonyDriver
    let sequencer: ShotSequencer<ManualClock>

    init() async throws {
        let clock = self.clock
        camera = FakeCamera(behavior: .instant, sleep: { duration in
            try await clock.sleep(until: clock.now.advanced(by: duration), tolerance: nil)
        })
        driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        sequencer = ShotSequencer(driver: driver, clock: clock)
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

    private func snapshot() async -> ShutterSnapshot {
        await sequencer.currentSnapshot()
    }

    @Test("Single tap holds focus for the grace period, then releases it")
    func singleTap() async throws {
        await input(.touchDown)
        #expect(await commands() == ["01 07"])
        #expect(await eventually { await snapshot().phase == .focused })

        await input(.touchUp)
        await clock.advance(by: .milliseconds(300))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07"], "focus stays held inside the grace period")

        await clock.advance(by: .seconds(3))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 06"])
        let after = await snapshot()
        #expect(after.focusHeld == false)
        #expect(after.sent == 0)
    }

    @Test("Double tap: full press on the second touch-down, no second half-press")
    func doubleTap() async throws {
        await input(.touchDown, .touchUp)
        await clock.advance(by: .milliseconds(100))
        await input(.touchDown)
        #expect(await eventually { await snapshot().sent == 1 })
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"],
                "half-down, full-down, full-up, half-up")
        let after = await snapshot()
        #expect(after.confirmed == 1)
        guard case .result(.acknowledged) = after.phase else {
            Issue.record("expected an acknowledged result, got \(after.phase)")
            return
        }

        // The finger lifting after the second tap does nothing.
        await input(.touchUp)
        await clock.advance(by: .seconds(5))
        #expect(await commands().count == 4)
    }

    @Test("A second tap after the window is a new single tap, not a shot")
    func slowSecondTap() async throws {
        await input(.touchDown, .touchUp)
        await clock.advance(by: .milliseconds(400))
        await input(.touchDown, .touchUp)
        #expect(await commands() == ["01 07"], "focus is still held, so no second half-press")
        #expect(await snapshot().sent == 0)
    }

    @Test("Shoot with nothing held runs half-then-full itself")
    func shootAction() async throws {
        await input(.shoot)
        #expect(await eventually { await snapshot().sent == 1 })
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"])
        #expect(await snapshot().confirmed == 1)
    }

    @Test("Shoot while focus is held sends only the full press")
    func shootFromHeldFocus() async throws {
        await input(.touchDown, .touchUp)
        await clock.advance(by: .milliseconds(300))
        await input(.shoot)
        #expect(await eventually { await snapshot().sent == 1 })
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"])
    }

    private func tapToShoot() async {
        var configuration = SequencerConfiguration()
        configuration.tapShoots = true
        await sequencer.setConfiguration(configuration)
    }

    @Test("Tap to shoot: one tap focuses on touch-down and shoots on lift")
    func tapToShootSingleTap() async throws {
        await tapToShoot()
        await input(.touchDown)
        #expect(await commands() == ["01 07"], "the half-press goes out on touch-down")
        await input(.touchUp)
        #expect(await eventually { await snapshot().sent == 1 })
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"],
                "one half-press, then full-down, full-up, half-up")
        let after = await snapshot()
        #expect(after.confirmed == 1)
        #expect(after.focusHeld == false)
        #expect(after.hint == nil, "the focus ack that came before the lift counts")

        // No double-tap window: nothing more goes out afterwards.
        await clock.advance(by: .seconds(5))
        await awaitIdle(sequencer)
        #expect(await commands().count == 4)
    }

    @Test("Tap to shoot: each tap is its own shot")
    func tapToShootTwoTaps() async throws {
        await tapToShoot()
        await input(.touchDown, .touchUp)
        #expect(await eventually { await snapshot().sent == 1 })
        await awaitIdle(sequencer)
        await clock.advance(by: .seconds(2))
        await input(.touchDown, .touchUp)
        #expect(await eventually { await snapshot().sent == 2 })
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06", "01 07", "01 09", "01 08", "01 06"])
    }

    @Test("Tap to shoot: a touch that moved (a scroll) releases focus and does not shoot")
    func tapToShootScroll() async throws {
        await tapToShoot()
        await input(.touchDown, .touchMoved)
        await awaitIdle(sequencer)
        await clock.advance(by: .seconds(5))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 06"])
        #expect(await snapshot().sent == 0)
    }

    @Test("Without Tap to shoot, a touch that moved is an ordinary single tap")
    func scrollWithoutTapToShoot() async throws {
        await input(.touchDown, .touchMoved)
        await clock.advance(by: .milliseconds(300))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07"], "focus is held for the grace period")
        #expect(await snapshot().focusHeld)
    }

    @Test("Tap to shoot: hand Double Tap still focuses, then shoots")
    func tapToShootHandGesture() async throws {
        await tapToShoot()
        await input(.shoot)
        #expect(await eventually { await snapshot().sent == 1 })
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"])
    }

    /// A camera slow to focus, so a shot is still in flight for a while.
    private func slowFocus() async {
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .milliseconds(500), shutterAckDelay: .zero))
    }

    private let shot = ["01 07", "01 09", "01 08", "01 06"]

    @Test("Tap to shoot: a tap while the last shot goes out is the next shot")
    func tapToShootDuringShot() async throws {
        await slowFocus()
        await tapToShoot()
        await input(.touchDown, .touchUp)
        await input(.touchDown, .touchUp)
        #expect(await snapshot().sent == 0, "the first shot still waits for focus")
        await clock.advance(by: .milliseconds(500))
        #expect(await eventually { await snapshot().sent == 1 })
        #expect(await eventually { await commands().count == 5 }, "the second half-press")
        await clock.advance(by: .milliseconds(500))
        #expect(await eventually { await snapshot().sent == 2 })
        await awaitIdle(sequencer)
        #expect(await commands() == shot + shot)

        // Only taps count: nothing more goes out.
        await clock.advance(by: .seconds(5))
        await awaitIdle(sequencer)
        #expect(await commands().count == 8)
    }

    @Test("Tap to shoot: a finger still down when the shot ends shoots on its lift")
    func tapToShootLiftAfterShot() async throws {
        await slowFocus()
        await tapToShoot()
        await input(.touchDown, .touchUp)
        await input(.touchDown)
        await clock.advance(by: .milliseconds(500))
        #expect(await eventually { await snapshot().sent == 1 })
        await awaitIdle(sequencer)
        #expect(await commands() == shot, "nothing more while the finger is down")
        await input(.touchUp)
        #expect(await eventually { await commands().count == 5 })
        await clock.advance(by: .milliseconds(500))
        #expect(await eventually { await snapshot().sent == 2 })
    }

    @Test("Tap to shoot: a touch during a shot that slides off adds no shot")
    func tapToShootSlideOffDuringShot() async throws {
        await slowFocus()
        await tapToShoot()
        await input(.touchDown, .touchUp)
        await input(.touchDown, .touchMoved)
        await clock.advance(by: .milliseconds(500))
        #expect(await eventually { await snapshot().sent == 1 })
        await clock.advance(by: .seconds(5))
        await awaitIdle(sequencer)
        #expect(await commands() == shot)
        #expect(await snapshot().sent == 1)
    }

    @Test("A hand Double Tap while a shot goes out is the next shot")
    func shootDuringShot() async throws {
        await slowFocus()
        await input(.shoot)
        await input(.shoot)
        #expect(await snapshot().sent == 0, "the first shot still waits for focus")
        await clock.advance(by: .milliseconds(500))
        #expect(await eventually { await snapshot().sent == 1 })
        #expect(await eventually { await commands().count == 5 }, "the second half-press")
        await clock.advance(by: .milliseconds(500))
        #expect(await eventually { await snapshot().sent == 2 })
        await awaitIdle(sequencer)
        #expect(await commands() == shot + shot)
    }

    private func bulbMode(_ seconds: Int, delay: Int? = nil) async {
        var configuration = SequencerConfiguration()
        configuration.bulbDuration = .seconds(seconds)
        configuration.releaseDelay = delay.map { .seconds($0) }
        await sequencer.setConfiguration(configuration)
    }

    private func bulbOpen() async -> (since: Date, ends: Date)? {
        if case .bulbOpen(let since, let ends) = await snapshot().phase { return (since, ends) }
        return nil
    }

    @Test("Photo mode: holding the shutter only holds focus, it never opens bulb")
    func holdIsNotBulb() async throws {
        await input(.touchDown)
        await clock.advance(by: .seconds(2))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07"])
        #expect(await bulbOpen() == nil)
    }

    /// One press and release: open on the first, close on the second.
    private let bulbPress = ["01 07", "01 09", "01 08", "01 06"]

    @Test("Bulb mode: one tap opens the bulb, it counts down and closes by itself")
    func timedBulb() async throws {
        await camera.setBehavior(bulbCamera())
        await bulbMode(5)
        await input(.touchDown, .touchUp)
        await awaitIdle(sequencer)
        #expect(await commands() == bulbPress, "a press and release opens the shutter (toggle)")
        #expect(await camera.isBulbOpen)
        let open = try #require(await bulbOpen())
        #expect(open.ends.timeIntervalSince(open.since) == 5)

        await clock.advance(by: .seconds(4))
        await awaitIdle(sequencer)
        #expect(await commands().count == 4, "still open before the time is up")

        await clock.advance(by: .seconds(1))
        #expect(await eventually { await commands() == bulbPress + bulbPress })
        await awaitIdle(sequencer)
        #expect(await camera.isBulbOpen == false, "the second press closed it")
        let after = await snapshot()
        #expect(after.sent == 1)
        #expect(after.confirmed == 1)
        #expect(await bulbOpen() == nil)
    }

    /// The fake camera set to BULB, acks at once.
    private func bulbCamera(shutterAck: Bool = true) -> FakeCamera.Behavior {
        var behavior = FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: shutterAck ? .zero : nil)
        behavior.bulbMode = true
        return behavior
    }

    @Test("Bulb mode: without a shutter ack the bulb is not shown open and no closing press is sent")
    func timedBulbNeverOpened() async throws {
        await camera.setBehavior(bulbCamera(shutterAck: false))
        await bulbMode(5)
        await input(.touchDown, .touchUp)
        await clock.advance(by: .seconds(3))
        #expect(await eventually { await snapshot().lastResult == .unconfirmed(.shutterTimedOut) })
        await awaitIdle(sequencer)
        #expect(await bulbOpen() == nil)
        await clock.advance(by: .seconds(10))
        await sequencer.linkRestored()
        await awaitIdle(sequencer)
        // The open press and its release, then only the reconnect's release:
        // a second press would open a bulb nobody closes.
        #expect(await commands() == bulbPress + ["01 08", "01 06"])
        #expect(await camera.isBulbOpen == false)
    }

    @Test("Bulb mode: a tap while the bulb is open closes it early")
    func timedBulbClosedEarly() async throws {
        await bulbMode(60)
        await input(.touchDown, .touchUp)
        await awaitIdle(sequencer)
        #expect(await bulbOpen() != nil)
        await clock.advance(by: .seconds(3))
        await input(.touchDown, .touchUp)
        await awaitIdle(sequencer)
        #expect(await commands() == bulbPress + bulbPress)
        await clock.advance(by: .seconds(60))
        await awaitIdle(sequencer)
        #expect(await commands().count == 8, "the bulb timer does not fire a second close")
    }

    @Test("Bulb mode with a release delay: the delay counts down, then the bulb opens")
    func timedBulbAfterDelay() async throws {
        await bulbMode(2, delay: 3)
        await input(.shoot)
        guard case .countdown = await snapshot().phase else {
            Issue.record("expected the release delay first, got \(await snapshot().phase)")
            return
        }
        #expect(await commands().isEmpty)
        await clock.advance(by: .seconds(3))
        #expect(await eventually { await self.bulbOpen() != nil })
        #expect(await commands() == bulbPress)
        #expect(await snapshot().lastShotDelayed)
        await clock.advance(by: .seconds(2))
        #expect(await eventually { await commands().count == 8 })
    }

    @Test("Bulb mode: a tap during the release delay cancels it, nothing opens")
    func timedBulbDelayCancelled() async throws {
        await bulbMode(2, delay: 10)
        await input(.touchDown, .touchUp)
        await clock.advance(by: .seconds(1))
        await input(.touchDown, .touchUp)
        await clock.advance(by: .seconds(15))
        await awaitIdle(sequencer)
        #expect(await bulbOpen() == nil)
        #expect(await snapshot().sent == 0)
        #expect(!(await commands()).contains("01 09"))
    }

    @Test("A missing shutter ack is reported as not confirmed, and a late ack upgrades it")
    func lateAck() async throws {
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: nil))
        await input(.shoot)
        await clock.advance(by: .seconds(3))
        #expect(await eventually { await snapshot().sent == 1 })
        await awaitIdle(sequencer)
        var after = await snapshot()
        #expect(after.confirmed == 0)
        #expect(after.lastResult == .unconfirmed(.shutterTimedOut))
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"], "buttons are released anyway")

        await camera.notify(Sony.Status.shutterActive)
        #expect(await eventually { await snapshot().confirmed == 1 })
        after = await snapshot()
        guard case .acknowledged = after.lastResult else {
            Issue.record("expected the late ack to upgrade the shot, got \(String(describing: after.lastResult))")
            return
        }
    }

    @Test("Acks are only matched inside the window our own press opened")
    func staleAckIgnored() async throws {
        await camera.notify(Sony.Status.shutterActive)
        await settle()
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: nil))
        await input(.shoot)
        await clock.advance(by: .seconds(3))
        await awaitIdle(sequencer)
        #expect(await snapshot().lastResult == .unconfirmed(.shutterTimedOut))
    }

    @Test("Focus ack timeout: the full press still goes out and the result is truthful")
    func focusTimeout() async throws {
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: nil, shutterAckDelay: nil))
        await input(.shoot)
        await clock.advance(by: .seconds(2))
        #expect(await eventually { await camera.commands().count == 2 }, "full press after the focus timeout")
        await clock.advance(by: .seconds(3))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 09", "01 08", "01 06"])
        let after = await snapshot()
        #expect(after.lastResult == .unconfirmed(.focusTimedOut))
        #expect(after.hint == .focusAckTimedOut)
    }

    @Test("Bluetooth Rmt Ctrl off: the shot fails and nothing is counted")
    func remoteControlOff() async throws {
        await camera.setBehavior(FakeCamera.Behavior(remoteControlOff: true))
        await input(.shoot)
        await awaitIdle(sequencer)
        let after = await snapshot()
        #expect(after.lastResult == .failed(.remoteControlOff))
        #expect(after.sent == 0)
    }

    @Test("Link lost after the full press: not confirmed, link lost")
    func linkLostMidShot() async throws {
        await camera.setBehavior(FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .zero,
                                                      dropLinkOnFullPress: true))
        await input(.shoot)
        await clock.advance(by: .seconds(3))
        await awaitIdle(sequencer)
        let after = await snapshot()
        #expect(after.lastResult == .unconfirmed(.linkLost))
        #expect(after.sent == 1)
        #expect(after.confirmed == 0)
    }

    @Test("The first action after a reconnect releases every button")
    func releaseAfterReconnect() async throws {
        await sequencer.linkLost()
        await camera.clearReceived()
        await sequencer.linkRestored()
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 08", "01 06"])
    }

    @Test("Leaving the scene with focus held releases every button")
    func sceneInactive() async throws {
        await input(.touchDown, .touchUp)
        await input(.sceneInactive)
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 08", "01 06"])
        #expect(await snapshot().focusHeld == false)
    }

    @Test("AF hold: a single tap toggles focus")
    func afHold() async throws {
        var configuration = SequencerConfiguration()
        configuration.afHold = true
        await sequencer.setConfiguration(configuration)

        await input(.touchDown, .touchUp)
        await clock.advance(by: .seconds(10))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07"], "no grace timer with AF hold")

        await input(.touchDown, .touchUp)
        await clock.advance(by: .milliseconds(300))
        await awaitIdle(sequencer)
        #expect(await commands() == ["01 07", "01 06"])
    }
}
