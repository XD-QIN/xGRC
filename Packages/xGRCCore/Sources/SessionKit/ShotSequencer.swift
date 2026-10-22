import BLEKit
import CameraKit
import Foundation
import Persistence

/// Raw input from the shutter control. The button style reports touches; the
/// sequencer alone decides what is a single tap or a double tap, and in bulb
/// mode what opens and closes the bulb, so the whole gesture table is
/// testable on an injected clock.
public enum ShutterInput: Hashable, Sendable {
    case touchDown
    case touchUp
    /// The touch lifted well off the shutter, or the system took it (a
    /// scroll that began on the button): a touch-up, except that with Tap to
    /// shoot it does not shoot and the half-press it sent is released.
    case touchMoved
    /// The control's primary action: hand Double Tap, VoiceOver activate, an intent.
    case shoot
    /// The scene left the active state (Return to Clock, app backgrounded).
    case sceneInactive
    /// Accessibility action *Focus*: the same as a single tap.
    case focus
    /// Accessibility action *Start/Stop bulb* (bulb mode only).
    case toggleBulb
    /// Accessibility action *Cancel countdown*; also ends bulb and releases focus.
    case cancel
}

public enum ShutterPhase: Hashable, Sendable {
    /// Nothing held.
    case idle
    /// Half-press sent, no focus confirmation yet.
    case focusing
    /// The camera confirmed focus.
    case focused
    /// A shot is in flight.
    case shooting
    /// A timed bulb is open; it closes at `ends`.
    case bulbOpen(since: Date, ends: Date)
    /// A release-delay countdown runs; the shot (or the bulb) fires at `ends`.
    case countdown(ends: Date, total: Duration)
    /// The outcome of the last shot, shown briefly.
    case result(ShotResult)
}

/// One-time hints the UI shows (architecture doc § Gesture timing and precedence).
public enum ShutterHint: Hashable, Sendable {
    /// The brand has no half-press; single tap does nothing.
    case noHalfPress
    /// The focus ack timed out; the camera may use back-button AF.
    case focusAckTimedOut
    /// A bulb may have been open when the link dropped, and the camera
    /// cannot report its shutter (Nikon Time): the close sent on reconnect
    /// opens a new exposure if the camera had already ended it.
    case checkBulb
}

/// What the UI renders.
public struct ShutterSnapshot: Hashable, Sendable {
    public var phase: ShutterPhase = .idle
    /// Every press that went out, including assumed ones.
    public var sent = 0
    /// Presses the camera acknowledged.
    public var confirmed = 0
    public var focusHeld = false
    public var lastResult: ShotResult?
    public var hint: ShutterHint?
    /// The last shot came from a release-delay countdown (one haptic on release).
    public var lastShotDelayed = false

    public init() {}
}

/// Timing values from architecture doc § Gesture timing and precedence.
public struct SequencerConfiguration: Hashable, Sendable {
    public var doubleTapWindow: Duration = .milliseconds(300)
    public var focusGrace: Duration = .seconds(3)
    public var focusAckTimeout: Duration = .seconds(2)
    public var lateAckWindow: Duration = .seconds(10)
    public var resultDisplay: Duration = .milliseconds(1500)
    /// Bulb mode: one tap opens the bulb, it counts down this long and
    /// closes by itself. `nil` = off (photo mode). Ignored on a camera
    /// without bulb.
    public var bulbDuration: Duration?
    /// The longest bulb the sequencer will hold open (99 min 59 s).
    public static let bulbLimit: Duration = .seconds(AppSettings.maxBulbSeconds)
    /// Single tap toggles focus instead of holding it for `focusGrace`.
    public var afHold = false
    /// *Tap to shoot* (watch): a single tap focuses on touch-down and
    /// shoots on touch-up, waiting for the focus first. No double tap.
    public var tapShoots = false
    /// Release delay, 1–60 s; `nil` = off. Never applies to intervalometer frames.
    public var releaseDelay: Duration?

    public init() {}
}

/// Owns all shutter timing: gestures, acks, grace period, timed bulb, late acks.
/// Brand-agnostic: it executes the driver's `ShotScript`. The clock is
/// injected so tests are deterministic.
public actor ShotSequencer<C: Clock> where C.Duration == Duration {
    private enum Gesture: Equatable {
        case none
        /// First touch is down.
        case pressing
        /// First touch is up; the double-tap window runs.
        case awaitingSecondTap
        case shooting
        case latched
        case countingDown
    }

    private enum TimerAction {
        case doubleTapWindow, grace, bulbEnd, countdown
    }

    private struct Waiter {
        let matches: @Sendable (CameraEvent) -> Bool
        let since: Int
        let continuation: CheckedContinuation<(at: C.Instant, event: CameraEvent)?, Never>
    }

    /// What a step list leaves behind when a write fails part way.
    private enum Cleanup {
        case none
        /// A shot or a half-press: every button up.
        case releaseAll
        /// A latch: close the bulb once its press went out (or may have),
        /// else every button up.
        case bulb
    }

    private struct StepOutcome {
        var mark = 0
        var fullSent = false
        /// The full press timed out: it may or may not have reached the camera.
        var fullSentUncertain = false
        var fullSentAt: C.Instant?
        /// Writes that failed, counted even when errors are ignored.
        var failedWrites = 0
        var ignoredError: Error?
        var focusLatency: Duration?
        var focusAckFailed = false
        var shutterLatency: Duration?
        var shutterAckFailed = false
        var heldFor: Duration = .zero
        var error: Error?
    }

    public let driver: any CameraDriver
    public let clock: C
    public private(set) var configuration: SequencerConfiguration

    private let script: ShotScript
    private let updates = Broadcaster<ShutterSnapshot>(replayLast: true)
    private var snapshot = ShutterSnapshot()

    private var gesture: Gesture = .none
    private var focusHeldBeforeTap = false
    /// Tap to shoot: the event mark of the touch's own half-press, so the
    /// shot waits for that press's focus ack even if it already arrived.
    private var tapFocusMark: Int?
    /// Tap to shoot: a touch came down while a shot was in flight.
    private var tapDuringShot = false
    /// A tap (Tap to shoot) or a hand Double Tap came while a shot was in
    /// flight, so the next shot starts when this one finishes. One is
    /// kept; more add nothing.
    private var queuedShot = false
    /// The running countdown opens a bulb when it ends instead of shooting.
    private var countdownOpensBulb = false
    /// How long the bulb being opened stays open.
    private var bulbLength: Duration = .zero
    private var ignoreNextTouchUp = false
    private var timer: Task<Void, Never>?
    private var timerGeneration = 0
    private var resultTimer: Task<Void, Never>?
    private var lateAck: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var eventPump: Task<Void, Never>?

    private var eventSeq = 0
    private var recentEvents: [(seq: Int, event: CameraEvent, at: C.Instant)] = []
    private var waiters: [UUID: Waiter] = [:]
    private var shownHints: Set<ShutterHint> = []
    private let now: @Sendable () -> Date
    /// A latch press went out (or may have) and no unlatch has completed
    /// since: the shutter may still be open, even across a link loss.
    private var bulbMayBeOpen = false
    /// The hold of the intervalometer's bulb frame, cancelled by `cancelFrameHold()`.
    private var frameHold: Task<Void, Never>?
    /// Bumped by every `cancelFrameHold()`: a frame queued before a stop
    /// sees a newer count and does not run.
    private var frameStops = 0
    /// A toggling latch went out without its shutter ack: a late ack means
    /// the shutter did open, so a link loss in the meantime must leave the
    /// bulb to the reconnect.
    private var awaitingLateBulb = false

    public init(driver: any CameraDriver, clock: C, configuration: SequencerConfiguration = .init(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.driver = driver
        self.clock = clock
        self.configuration = configuration
        self.script = driver.shotScript
        self.now = now
    }

    /// Starts listening to the driver's events. Call once.
    public func start() {
        guard eventPump == nil else { return }
        let events = driver.events()
        eventPump = Task { [weak self] in
            for await event in events {
                await self?.handle(event: event)
            }
        }
        publish()
    }

    public func stop() {
        eventPump?.cancel()
        timer?.cancel()
        resultTimer?.cancel()
        lateAck?.cancel()
        for waiter in waiters.values { waiter.continuation.resume(returning: nil) }
        waiters.removeAll()
        updates.finish()
    }

    public nonisolated func snapshots() -> AsyncStream<ShutterSnapshot> {
        updates.stream()
    }

    public func currentSnapshot() -> ShutterSnapshot { snapshot }

    public func setConfiguration(_ configuration: SequencerConfiguration) {
        self.configuration = configuration
    }

    /// Resolves when every queued GATT operation has finished. For tests.
    public func idle() async {
        while let current = work {
            await current.value
            if work == current { break }
        }
    }

    // MARK: Input

    public func handle(_ input: ShutterInput) {
        switch input {
        case .touchDown: touchDown()
        case .touchUp: touchUp()
        case .touchMoved: touchMoved()
        case .shoot:
            // Hand Double Tap while a shot goes out: the next photo, not nothing.
            if gesture == .shooting { queuedShot = true } else { shootAction() }
        case .sceneInactive: sceneInactive()
        case .focus: focusAction()
        case .toggleBulb: toggleBulb()
        case .cancel: sceneInactive()
        }
    }

    private func focusAction() {
        guard gesture == .none else { return }
        guard script.focusSupported else {
            show(.noHalfPress)
            return
        }
        focusHeldBeforeTap = snapshot.focusHeld
        if !snapshot.focusHeld { pressFocus() }
        singleTapEnded()
    }

    private func toggleBulb() {
        switch gesture {
        case .latched:
            unlatch()
        case .none where bulbMode:
            cancelTimer()
            startBulb()
        default:
            break
        }
    }

    /// A bulb duration is set and the camera can hold the shutter open.
    public var bulbMode: Bool {
        guard let duration = configuration.bulbDuration, duration > .zero else { return false }
        return canHoldBulb
    }

    /// The camera can hold the shutter open: a latch and a bulb capability.
    public var canHoldBulb: Bool {
        guard !script.latch.isEmpty else { return false }
        return !type(of: driver).descriptor.capabilities.isDisjoint(with: [.bulb, .bulbAsTime])
    }

    /// A bulb is open, opening, or may still be open after a link loss:
    /// the session must reconnect to close it.
    public var mayHaveShutterOpen: Bool {
        bulbMayBeOpen || gesture == .latched
    }

    /// A countdown runs or a bulb is open (or opening).
    public var isHoldingShutter: Bool {
        gesture == .latched || gesture == .countingDown
    }

    /// The link dropped: nothing in flight can be trusted.
    public func linkLost() {
        cancelTimer()
        dropQueuedShot()
        lateAck?.cancel()
        if awaitingLateBulb {
            // The late ack can no longer arrive; the reconnect checks.
            awaitingLateBulb = false
            bulbMayBeOpen = true
        }
        // An open bulb stays open on the camera; the reconnect closes it.
        // A toggling unlatch (Nikon) is only sent once the press is known
        // to have gone out, which the latch itself records.
        if gesture == .latched, !script.unlatchToggles { bulbMayBeOpen = true }
        if gesture == .countingDown {
            gesture = .none
            snapshot.focusHeld = false
            finish(.cancelled)
            return
        }
        if gesture != .shooting { gesture = .none }
        ignoreNextTouchUp = false
        snapshot.focusHeld = false
        if case .result = snapshot.phase {} else { snapshot.phase = .idle }
        publish()
    }

    /// The first action after every reconnect is a release of every button,
    /// after closing a bulb the link loss may have left open.
    public func linkRestored() {
        let steps = script.releaseAll
        enqueue { sequencer in
            if await sequencer.bulbMayBeOpen { await sequencer.closeBulbAfterReconnect() }
            _ = await sequencer.run(steps, ignoringErrors: true)
        }
    }

    private func touchDown() {
        switch gesture {
        case .shooting:
            // Tap to shoot: every tap is a photo, even one made while the
            // previous shot is still going out.
            if configuration.tapShoots { tapDuringShot = true }
        case .pressing:
            return
        case .countingDown:
            // Tap during countdown: cancel.
            ignoreNextTouchUp = true
            cancelCountdown()
        case .latched:
            // Tap while the bulb is open: close it early.
            ignoreNextTouchUp = true
            unlatch()
        case .awaitingSecondTap:
            // Second touch-down: the full press goes out now, no second half-press.
            cancelTimer()
            ignoreNextTouchUp = true
            shootOrCountDown()
        case .none where bulbMode:
            // Bulb mode: one tap opens the bulb (after the release delay).
            cancelTimer()
            ignoreNextTouchUp = true
            startBulb()
        case .none:
            cancelTimer()
            focusHeldBeforeTap = snapshot.focusHeld
            gesture = .pressing
            tapFocusMark = nil
            if script.focusSupported, !snapshot.focusHeld {
                if configuration.tapShoots { tapFocusMark = eventSeq }
                pressFocus()
            }
        }
    }

    private func touchUp() {
        if ignoreNextTouchUp {
            ignoreNextTouchUp = false
            return
        }
        if tapDuringShot {
            tapDuringShot = false
            if gesture == .shooting { queuedShot = true } else { shootQueued() }
            return
        }
        guard gesture == .pressing else { return }
        cancelTimer()
        if configuration.tapShoots {
            // Tap to shoot: the lift fires, after the focus this touch started.
            gesture = .none
            let mark = tapFocusMark
            tapFocusMark = nil
            shootOrCountDown(awaitingFocusSince: mark)
            return
        }
        gesture = .awaitingSecondTap
        startTimer(configuration.doubleTapWindow, .doubleTapWindow)
    }

    private func touchMoved() {
        if tapDuringShot {
            tapDuringShot = false
            return
        }
        guard configuration.tapShoots, !ignoreNextTouchUp, gesture == .pressing else {
            touchUp()
            return
        }
        cancelTimer()
        gesture = .none
        tapFocusMark = nil
        if snapshot.focusHeld, !focusHeldBeforeTap { releaseFocus() }
    }

    /// What the primary action did. *Shoot* from an intent reports it.
    public enum ShootResponse: Hashable, Sendable {
        /// A shot is in flight; the action did nothing.
        case ignored
        case shotStarted
        case countdownStarted
        case countdownCancelled
        case bulbStarted
        case bulbClosed
    }

    /// The primary action, reporting what it did.
    @discardableResult
    public func shoot() -> ShootResponse {
        shootAction()
    }

    @discardableResult
    private func shootAction() -> ShootResponse {
        switch gesture {
        case .shooting:
            return .ignored
        case .countingDown:
            // Hand Double Tap during countdown: cancel.
            cancelCountdown()
            return .countdownCancelled
        case .latched:
            unlatch()
            return .bulbClosed
        case .pressing:
            cancelTimer()
            ignoreNextTouchUp = true
            return shootOrCountDown()
        case .none where bulbMode:
            cancelTimer()
            return startBulb()
        case .awaitingSecondTap, .none:
            cancelTimer()
            return shootOrCountDown()
        }
    }

    private func sceneInactive() {
        cancelTimer()
        ignoreNextTouchUp = false
        dropQueuedShot()
        guard gesture != .shooting else { return }
        let wasLatched = gesture == .latched || gesture == .countingDown
        let anythingHeld = wasLatched || snapshot.focusHeld || gesture == .pressing || bulbMayBeOpen
        // An open bulb closes with the brand's unlatch: on Nikon (Time) and
        // Ricoh (stop) a plain release would leave the shutter open.
        let closesBulb = gesture == .latched || bulbMayBeOpen
        let steps = script.releaseAll
        gesture = .none
        guard anythingHeld else { return }
        snapshot.focusHeld = false
        snapshot.phase = wasLatched ? .result(.cancelled) : .idle
        publish()
        enqueue { sequencer in
            if closesBulb {
                await sequencer.closeBulbIfOpen()
            } else {
                _ = await sequencer.run(steps, ignoringErrors: true)
            }
        }
        if wasLatched { scheduleResultClear() }
    }

    // MARK: Timers

    private func startTimer(_ duration: Duration, _ action: TimerAction) {
        timer?.cancel()
        timerGeneration += 1
        let generation = timerGeneration
        let clock = self.clock
        let deadline = clock.now.advanced(by: duration)
        timer = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return
            }
            await self?.timerFired(action, generation: generation)
        }
    }

    private func cancelTimer() {
        timerGeneration += 1
        timer?.cancel()
        timer = nil
    }

    private func timerFired(_ action: TimerAction, generation: Int) {
        guard generation == timerGeneration else { return }
        timer = nil
        switch action {
        case .doubleTapWindow:
            guard gesture == .awaitingSecondTap else { return }
            gesture = .none
            singleTapEnded()
        case .grace:
            guard gesture == .none, snapshot.focusHeld else { return }
            releaseFocus()
        case .bulbEnd:
            guard gesture == .latched else { return }
            unlatch()
        case .countdown:
            guard gesture == .countingDown else { return }
            if countdownOpensBulb {
                latch(delayed: true)
            } else {
                beginShot(delayed: true)
            }
        }
    }

    // MARK: Release delay

    /// - Parameter awaitingFocusSince: tap to shoot: the mark of the tap's
    ///   own half-press, whose focus the shot waits for.
    @discardableResult
    private func shootOrCountDown(awaitingFocusSince focusMark: Int? = nil) -> ShootResponse {
        if let delay = configuration.releaseDelay, delay > .zero {
            startCountdown(delay, opensBulb: false)
            return .countdownStarted
        }
        beginShot(awaitingFocusSince: focusMark)
        return .shotStarted
    }

    /// Bulb mode: the release delay first if one is set, then the bulb.
    @discardableResult
    private func startBulb() -> ShootResponse {
        if let delay = configuration.releaseDelay, delay > .zero {
            startCountdown(delay, opensBulb: true)
        } else {
            latch()
        }
        return .bulbStarted
    }

    /// Focus already held from the first tap stays held through the countdown;
    /// the shot sequence releases it.
    private func startCountdown(_ delay: Duration, opensBulb: Bool) {
        gesture = .countingDown
        countdownOpensBulb = opensBulb
        cancelLateAck()
        resultTimer?.cancel()
        snapshot.phase = .countdown(ends: now().addingTimeInterval(Self.seconds(delay)), total: delay)
        publish()
        startTimer(delay, .countdown)
    }

    private func cancelCountdown() {
        cancelTimer()
        gesture = .none
        snapshot.focusHeld = false
        finish(.cancelled)
        let steps = script.releaseAll
        enqueue { sequencer in
            _ = await sequencer.run(steps, ignoringErrors: true)
        }
    }

    static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func singleTapEnded() {
        guard script.focusSupported else {
            show(.noHalfPress)
            return
        }
        guard snapshot.focusHeld else { return }
        if configuration.afHold {
            // AF hold: a single tap toggles focus.
            if focusHeldBeforeTap { releaseFocus() }
        } else {
            startTimer(configuration.focusGrace, .grace)
        }
    }

    // MARK: Focus

    private func pressFocus() {
        snapshot.focusHeld = true
        snapshot.phase = .focusing
        publish()
        let steps = script.focusPress
        enqueue { sequencer in
            let outcome = await sequencer.run(steps, cleanup: .releaseAll)
            await sequencer.focusPressFinished(outcome.error)
        }
    }

    private func focusPressFinished(_ error: Error?) {
        guard let error else { return }
        snapshot.focusHeld = false
        finish(.failed(Self.shotError(error)))
    }

    private func releaseFocus() {
        snapshot.focusHeld = false
        if snapshot.phase == .focusing || snapshot.phase == .focused { snapshot.phase = .idle }
        publish()
        let steps = script.focusRelease
        enqueue { sequencer in
            _ = await sequencer.run(steps, ignoringErrors: true)
        }
    }

    // MARK: Shots

    /// - Parameter focusMark: tap to shoot: the half-press went out with
    ///   this tap at this event mark; wait for its focus unless the camera
    ///   already confirmed it.
    private func beginShot(delayed: Bool = false, awaitingFocusSince focusMark: Int? = nil) {
        gesture = .shooting
        cancelLateAck()
        resultTimer?.cancel()
        clearCheckBulbHint()
        snapshot.lastShotDelayed = delayed
        let fromFocus = snapshot.focusHeld
        let focusConfirmed = snapshot.phase == .focused
        snapshot.phase = .shooting
        publish()

        var steps: [ShotStep]
        var since: Int?
        if script.focusSupported {
            if !fromFocus {
                steps = script.focusPress + focusWait
            } else if let focusMark, !focusConfirmed {
                steps = focusWait
                since = focusMark
            } else {
                steps = []
            }
            steps += script.shootFromFocus + script.focusRelease
        } else {
            steps = script.shootWithoutFocus
        }
        let shot = steps
        let mark = since
        let confirms = ShotScript.confirmsShutter(shot)
        enqueue { sequencer in
            let outcome = await sequencer.run(shot, cleanup: .releaseAll, since: mark)
            await sequencer.shotFinished(outcome, confirms: confirms)
        }
    }

    /// After a half-press: the focus ack where the camera sends one, else a
    /// short settle so the camera can start AF before the full press.
    private var focusWait: [ShotStep] {
        if script.acknowledgesFocus {
            return [.awaitAck(.focus, timeout: configuration.focusAckTimeout, optional: true)]
        }
        return script.focusSettle > .zero ? [.hold(script.focusSettle)] : []
    }

    private func shotFinished(_ outcome: StepOutcome, confirms: Bool) {
        gesture = .none
        snapshot.focusHeld = false
        let result = Self.result(of: outcome, confirms: confirms)
        if outcome.focusAckFailed { show(.focusAckTimedOut) }
        finish(result)
        if case .unconfirmed(let reason) = result, reason != .linkLost {
            watchForLateAck(since: outcome.mark, sentAt: outcome.fullSentAt)
        }
        if queuedShot {
            queuedShot = false
            // A failed write is shown, not repeated into the same fault.
            if case .failed = result {} else { shootQueued() }
        }
    }

    /// The tap or Double Tap made during the last shot, as if it came now.
    private func shootQueued() {
        guard gesture == .none, !bulbMode else { return }
        shootOrCountDown()
    }

    private func dropQueuedShot() {
        tapDuringShot = false
        queuedShot = false
    }

    // MARK: Intervalometer frames

    /// One intervalometer frame, queued behind any gesture work so writes
    /// never interleave. No release delay. `focus` runs the focus step with
    /// its 2 s timeout (*AF each frame*); an `exposure` above 1 s runs as
    /// bulb (latch, hold, unlatch) on a camera that can hold the shutter
    /// open, else as a normal shot; `readyTimeout` waits for *shutter ready*
    /// on brands with a shutter ack.
    ///
    /// - Parameter stoppable: `cancelFrameHold()` stops this frame (the
    ///   intervalometer's); an intent's shot passes `false`.
    public func frame(focus: Bool, exposure: Duration?, readyTimeout: Duration?,
                      stoppable: Bool = true) async -> ShotResult {
        // The intervalometer stopped (its task is cancelled) before this call got here.
        if stoppable, Task.isCancelled { return .cancelled }
        let token: Int? = stoppable ? frameStops : nil
        var bulb: Duration?
        var steps: [ShotStep]
        if let exposure, exposure > .seconds(1), canHoldBulb {
            bulb = exposure
            steps = script.latch
        } else if script.focusSupported {
            steps = focus
                ? script.focusPress + focusWait + script.shootFromFocus + script.focusRelease
                : script.shootFromFocus
        } else {
            steps = script.shootWithoutFocus
        }
        let confirms = ShotScript.confirmsShutter(steps)
        var ready: [ShotStep] = []
        if let readyTimeout, confirms {
            ready = [.awaitAck(.ready, timeout: readyTimeout, optional: true)]
        }
        let frameSteps = steps
        let readySteps = ready
        let exposure = bulb
        return await withCheckedContinuation { continuation in
            enqueue { sequencer in
                let result = await sequencer.runFrame(frameSteps, bulb: exposure, ready: readySteps,
                                                      confirms: confirms, token: token)
                continuation.resume(returning: result)
            }
        }
    }

    /// Ends a bulb frame's hold at once (the intervalometer stopped): the
    /// frame closes the bulb now. A frame still queued does not open one.
    public func cancelFrameHold() {
        frameStops += 1
        frameHold?.cancel()
    }

    /// A stop came after this frame was queued.
    private func stopped(_ token: Int?) -> Bool {
        token.map { $0 != frameStops } ?? false
    }

    private func runFrame(_ steps: [ShotStep], bulb: Duration?, ready: [ShotStep], confirms: Bool,
                          token: Int?) async -> ShotResult {
        guard !stopped(token) else { return .cancelled }
        // An older shot's late-ack watcher must not take this frame's ack.
        cancelLateAck()
        var outcome: StepOutcome
        if let bulb {
            outcome = await run(steps, opensBulb: true, cleanup: .bulb)
            if script.unlatchToggles, !latchOpened(outcome) {
                // A toggling latch the camera never confirmed: nothing to close,
                // unless its ack is only late.
                bulbMayBeOpen = false
                if lateBulbPossible(outcome, confirms: confirms) {
                    await closeLateBulb(since: outcome.mark)
                }
            } else if outcome.error == nil {
                outcome.heldFor += await holdFrame(bulb, token: token)
                let close = await closeBulb()
                if close.failedWrites > 0 {
                    outcome.error = close.ignoredError ?? CameraError.transport(.disconnected(.other(code: 0)))
                } else if !ready.isEmpty {
                    _ = await run(ready, since: close.mark)
                }
            }
        } else {
            outcome = await run(steps + ready, cleanup: .releaseAll)
        }
        return frameFinished(outcome, confirms: confirms)
    }

    /// Holds a bulb frame open for `duration`, or until `cancelFrameHold()`.
    private func holdFrame(_ duration: Duration, token: Int?) async -> Duration {
        guard !stopped(token) else { return .zero }
        let clock = self.clock
        let start = clock.now
        let deadline = start.advanced(by: duration)
        let hold = Task { _ = try? await clock.sleep(until: deadline, tolerance: nil) }
        frameHold = hold
        await hold.value
        frameHold = nil
        return start.duration(to: clock.now)
    }

    private func frameFinished(_ outcome: StepOutcome, confirms: Bool) -> ShotResult {
        let result = Self.result(of: outcome, confirms: confirms)
        snapshot.lastShotDelayed = false
        finish(result)
        return result
    }

    /// Opens a timed bulb: the half-press first where the brand has one,
    /// then the brand's latch. The countdown starts once the shutter is open.
    private func latch(delayed: Bool = false) {
        gesture = .latched
        cancelLateAck()
        resultTimer?.cancel()
        clearCheckBulbHint()
        bulbLength = min(configuration.bulbDuration ?? .seconds(1), SequencerConfiguration.bulbLimit)
        snapshot.lastShotDelayed = delayed
        snapshot.phase = .shooting
        publish()
        let steps = script.focusSupported && !snapshot.focusHeld
            ? script.focusPress + focusWait + script.latch
            : script.latch
        let confirms = ShotScript.confirmsShutter(steps)
        enqueue { sequencer in
            let outcome = await sequencer.run(steps, opensBulb: true, cleanup: .bulb)
            await sequencer.latchFinished(outcome, confirms: confirms)
        }
    }

    private func latchFinished(_ outcome: StepOutcome, confirms: Bool) {
        let result = Self.result(of: outcome, confirms: confirms)
        count(result)
        snapshot.lastResult = result
        // Before the guard: a close queued while the shutter was opening
        // must not send a toggling press to a shutter that never opened.
        if script.unlatchToggles, !latchOpened(outcome) {
            bulbMayBeOpen = false
            if lateBulbPossible(outcome, confirms: confirms) { watchForLateBulb(since: outcome.mark) }
        }
        guard gesture == .latched else {
            // Closed (tap, scene change) while the shutter was still opening.
            return
        }
        if latchOpened(outcome), outcome.error == nil {
            let since = now()
            snapshot.phase = .bulbOpen(since: since, ends: since.addingTimeInterval(Self.seconds(bulbLength)))
            publish()
            startTimer(bulbLength, .bulbEnd)
        } else {
            gesture = .none
            snapshot.focusHeld = false
            snapshot.phase = .result(result)
            publish()
            scheduleResultClear()
        }
    }

    private func unlatch() {
        cancelTimer()
        gesture = .shooting
        enqueue { sequencer in
            await sequencer.closeBulbIfOpen()
            await sequencer.unlatchFinished()
        }
    }

    /// Runs the brand's unlatch. The bulb counts as closed once every write
    /// of it went out; until then a reconnect closes it again.
    @discardableResult
    private func closeBulb() async -> StepOutcome {
        let outcome = await run(script.unlatch, ignoringErrors: true)
        if outcome.failedWrites == 0 { bulbMayBeOpen = false }
        return outcome
    }

    /// The unlatch where a latch press went out, else every button up (the
    /// latch failed before its press, so a toggling unlatch would open one).
    private func closeBulbIfOpen() async {
        if bulbMayBeOpen {
            await closeBulb()
        } else {
            _ = await run(script.releaseAll, ignoringErrors: true)
        }
    }

    /// After a reconnect, closes a bulb the link loss may have left open.
    /// A toggling close sent to a shutter the camera already closed (it
    /// lost power, or ended the exposure itself) opens a new one. Where the
    /// camera reports its shutter (Sony), *shutter active* in answer to the
    /// close means exactly that, so it closes once more; *ready* means the
    /// close worked. Without that report (Nikon Time) the close goes out and
    /// the UI asks to check the camera.
    private func closeBulbAfterReconnect() async {
        let close = await closeBulb()
        guard script.unlatchToggles, close.failedWrites == 0 else { return }
        guard ShotScript.confirmsShutter(script.latch) else {
            snapshot.hint = .checkBulb
            publish()
            return
        }
        let answer = await waitForEvent(since: close.mark, timeout: Self.reconnectCloseWindow) {
            AckKind.shutter.isSatisfied(by: $0) || AckKind.ready.isSatisfied(by: $0)
        }
        if let answer, AckKind.shutter.isSatisfied(by: answer.event) {
            bulbMayBeOpen = true
            await closeBulb()
        }
    }

    /// How long a reconnect close waits for the camera's shutter state.
    static var reconnectCloseWindow: Duration { .seconds(3) }

    /// A toggling latch whose press went out but whose
    /// shutter ack did not come in time, on a camera that sends one: the
    /// ack may still come, and then the shutter is open.
    private func lateBulbPossible(_ outcome: StepOutcome, confirms: Bool) -> Bool {
        script.unlatchToggles && confirms && outcome.fullSent
    }

    /// Gesture bulbs: watches for a late shutter ack in the background and
    /// closes the bulb it reveals.
    private func watchForLateBulb(since mark: Int) {
        cancelLateAck()
        awaitingLateBulb = true
        let window = configuration.lateAckWindow
        lateAck = Task { [weak self] in
            guard let self else { return }
            let at = await self.waitForAck(.shutter, since: mark, timeout: window)
            guard !Task.isCancelled else { return }
            await self.lateBulbWatchEnded(opened: at != nil)
        }
    }

    private func lateBulbWatchEnded(opened: Bool) {
        guard awaitingLateBulb else { return }
        awaitingLateBulb = false
        guard opened else { return }
        bulbMayBeOpen = true
        enqueue { sequencer in await sequencer.closeBulbIfOpen() }
    }

    /// Intervalometer bulbs: the frame waits for a late ack itself, so the
    /// next frame never starts on an open shutter.
    private func closeLateBulb(since mark: Int) async {
        guard await waitForAck(.shutter, since: mark, timeout: configuration.lateAckWindow) != nil else { return }
        bulbMayBeOpen = true
        await closeBulb()
    }

    private func cancelLateAck() {
        lateAck?.cancel()
        lateAck = nil
        awaitingLateBulb = false
    }

    private func clearCheckBulbHint() {
        if snapshot.hint == .checkBulb { snapshot.hint = nil }
    }

    private func unlatchFinished() {
        gesture = .none
        // A tap made while the bulb closed was a close, not a new photo.
        dropQueuedShot()
        snapshot.focusHeld = false
        snapshot.phase = snapshot.lastResult.map(ShutterPhase.result) ?? .idle
        publish()
        scheduleResultClear()
    }

    private func finish(_ result: ShotResult) {
        count(result)
        snapshot.lastResult = result
        snapshot.phase = .result(result)
        publish()
        scheduleResultClear()
    }

    private func count(_ result: ShotResult) {
        if result.wasSent { snapshot.sent += 1 }
        if result.isConfirmed { snapshot.confirmed += 1 }
    }

    private func scheduleResultClear() {
        resultTimer?.cancel()
        let clock = self.clock
        let deadline = clock.now.advanced(by: configuration.resultDisplay)
        resultTimer = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return
            }
            await self?.clearResult()
        }
    }

    private func clearResult() {
        guard case .result = snapshot.phase else { return }
        snapshot.phase = snapshot.focusHeld ? .focusing : .idle
        publish()
    }

    /// A shutter ack inside the late-ack window upgrades an unconfirmed shot.
    private func watchForLateAck(since mark: Int, sentAt: C.Instant?) {
        cancelLateAck()
        let window = configuration.lateAckWindow
        lateAck = Task { [weak self] in
            guard let self else { return }
            guard let at = await self.waitForAck(.shutter, since: mark, timeout: window),
                  !Task.isCancelled else { return }
            await self.upgradeLastShot(latency: sentAt.map { $0.duration(to: at) } ?? .zero)
        }
    }

    private func upgradeLastShot(latency: Duration) {
        guard case .unconfirmed = snapshot.lastResult else { return }
        let upgraded = ShotResult.acknowledged(focusLatency: nil, shutterLatency: latency)
        snapshot.confirmed += 1
        snapshot.lastResult = upgraded
        if case .result = snapshot.phase { snapshot.phase = .result(upgraded) }
        publish()
    }

    // MARK: Step execution

    private func enqueue(_ operation: @escaping @Sendable (ShotSequencer) async -> Void) {
        let previous = work
        work = Task {
            await previous?.value
            await operation(self)
        }
    }

    /// Runs `steps` in order. A failed write ends the list (unless errors
    /// are ignored) and runs `cleanup`, so no button is left held. With
    /// `opensBulb`, a full press that went out (or may have) marks the
    /// bulb as possibly open until an unlatch completes.
    private func run(_ steps: [ShotStep], ignoringErrors: Bool = false, opensBulb: Bool = false,
                     cleanup: Cleanup = .none, since mark: Int? = nil) async -> StepOutcome {
        var outcome = StepOutcome()
        outcome.mark = mark ?? eventSeq
        let start = clock.now
        for step in steps {
            switch step {
            case .write(let write):
                do {
                    try await driver.send(write)
                } catch {
                    outcome.failedWrites += 1
                    // A failed press may still have reached the camera. A
                    // non-toggling unlatch is harmless on a closed shutter.
                    if write.firesShutter, opensBulb, !script.unlatchToggles { bulbMayBeOpen = true }
                    if ignoringErrors {
                        outcome.ignoredError = outcome.ignoredError ?? error
                        continue
                    }
                    outcome.error = error
                    if write.firesShutter, Self.isTimeout(error) {
                        // The camera may have taken it: unconfirmed, not failed.
                        outcome.fullSent = true
                        outcome.fullSentUncertain = true
                        outcome.fullSentAt = clock.now
                    }
                    await clean(up: cleanup, after: outcome)
                    return outcome
                }
                if write.firesShutter {
                    outcome.fullSent = true
                    outcome.fullSentAt = clock.now
                    if opensBulb { bulbMayBeOpen = true }
                }
            case .awaitAck(let kind, let timeout, let optional):
                let at = await waitForAck(kind, since: outcome.mark, timeout: timeout)
                switch kind {
                case .focus:
                    if let at { outcome.focusLatency = start.duration(to: at) } else { outcome.focusAckFailed = true }
                case .shutter:
                    if let at {
                        outcome.shutterLatency = (outcome.fullSentAt ?? start).duration(to: at)
                    } else if !optional {
                        outcome.shutterAckFailed = true
                    }
                case .ready:
                    break
                }
            case .hold(let duration):
                try? await clock.sleep(until: clock.now.advanced(by: duration), tolerance: nil)
                outcome.heldFor += duration
            }
        }
        return outcome
    }

    private func clean(up cleanup: Cleanup, after outcome: StepOutcome) async {
        switch cleanup {
        case .none:
            break
        case .releaseAll:
            _ = await run(script.releaseAll, ignoringErrors: true)
        case .bulb:
            if latchOpened(outcome) {
                await closeBulb()
            } else {
                _ = await run(script.releaseAll, ignoringErrors: true)
            }
        }
    }

    /// The latch press may have opened the shutter, so the unlatch is due.
    /// A toggling unlatch (Nikon Time, Sony) sent to a closed shutter opens
    /// one, so it needs the press known to have gone out and, where the
    /// brand confirms the shutter (Sony), the camera's shutter ack.
    private func latchOpened(_ outcome: StepOutcome) -> Bool {
        guard outcome.fullSent else { return false }
        guard script.unlatchToggles else { return true }
        return !outcome.fullSentUncertain && !outcome.shutterAckFailed
    }

    static func isTimeout(_ error: Error) -> Bool {
        switch error {
        case CameraError.transport(.timeout), GATTError.timeout: true
        default: false
        }
    }

    private static func result(of outcome: StepOutcome, confirms: Bool) -> ShotResult {
        if let error = outcome.error {
            guard outcome.fullSent else { return .failed(shotError(error)) }
            return .unconfirmed(isTimeout(error) ? .shutterTimedOut : .linkLost)
        }
        guard confirms else { return .assumed(heldFor: outcome.heldFor) }
        if let latency = outcome.shutterLatency, !outcome.shutterAckFailed {
            return .acknowledged(focusLatency: outcome.focusLatency, shutterLatency: latency)
        }
        return .unconfirmed(outcome.focusAckFailed ? .focusTimedOut : .shutterTimedOut)
    }

    static func shotError(_ error: Error) -> ShotError {
        switch error {
        case CameraError.remoteControlOff: .remoteControlOff
        case CameraError.busy: .busy
        case CameraError.transport(let gatt): .transport(gatt)
        case let gatt as GATTError: .transport(gatt)
        default: .notConnected
        }
    }

    // MARK: Acks

    private func handle(event: CameraEvent) {
        eventSeq += 1
        let now = clock.now
        recentEvents.append((eventSeq, event, now))
        if recentEvents.count > 64 { recentEvents.removeFirst(recentEvents.count - 64) }

        for (id, waiter) in waiters where waiter.since < eventSeq && waiter.matches(event) {
            waiters[id] = nil
            waiter.continuation.resume(returning: (now, event))
        }

        switch event {
        case .focusAcquired where snapshot.focusHeld && snapshot.phase == .focusing:
            snapshot.phase = .focused
            publish()
        case .focusLost where snapshot.focusHeld && snapshot.phase == .focused:
            snapshot.phase = .focusing
            publish()
        default:
            break
        }
    }

    /// The instant the first matching event arrived after `since`, or `nil` on timeout.
    private func waitForAck(_ kind: AckKind, since mark: Int, timeout: Duration) async -> C.Instant? {
        await waitForEvent(since: mark, timeout: timeout) { kind.isSatisfied(by: $0) }?.at
    }

    /// The first event after `since` that `matches`, and when it arrived, or `nil` on timeout.
    private func waitForEvent(since mark: Int, timeout: Duration,
                              where matches: @escaping @Sendable (CameraEvent) -> Bool) async
        -> (at: C.Instant, event: CameraEvent)? {
        if let hit = recentEvents.first(where: { $0.seq > mark && matches($0.event) }) {
            return (hit.at, hit.event)
        }
        let id = UUID()
        let clock = self.clock
        let deadline = clock.now.advanced(by: timeout)
        let expiry = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return
            }
            await self?.expireWaiter(id)
        }
        defer { expiry.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[id] = Waiter(matches: matches, since: mark, continuation: continuation)
            }
        } onCancel: {
            Task { [weak self] in await self?.expireWaiter(id) }
        }
    }

    private func expireWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(returning: nil)
    }

    // MARK: Output

    private func show(_ hint: ShutterHint) {
        guard shownHints.insert(hint).inserted else { return }
        snapshot.hint = hint
        publish()
    }

    private func publish() {
        updates.yield(snapshot)
    }
}
