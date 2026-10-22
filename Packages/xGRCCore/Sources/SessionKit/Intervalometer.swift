import BLEKit
import CameraKit
import Foundation
import Persistence

extension IntervalometerPlan {
    var interval: Duration { .milliseconds(Int64(max(intervalSeconds, 1) * 1000)) }
    var initialWait: Duration { .milliseconds(Int64(max(initialWaitSeconds, 0) * 1000)) }
    var exposure: Duration? { exposureSeconds.map { .milliseconds(Int64($0 * 1000)) } }
}

public enum IntervalometerState: Hashable, Sendable {
    case idle
    /// Counting the initial wait.
    case waiting(until: Date)
    case running
    /// The link is down; frames are skipped and counted as missed.
    case paused
    case finished(IntervalometerEnd)
}

public enum IntervalometerEnd: Hashable, Sendable {
    case completed
    case stopped
    /// Three consecutive failed frames with the link up.
    case failures
}

/// What the intervalometer sheet and the Shutter page show.
public struct IntervalometerSnapshot: Hashable, Sendable {
    public var state: IntervalometerState = .idle
    public var plan: IntervalometerPlan?
    /// Frames due so far, including missed and failed ones.
    public var frame = 0
    /// Presses that went out, including assumed ones.
    public var sent = 0
    /// Frames the camera acknowledged.
    public var confirmed = 0
    /// Skipped while the link was down.
    public var missed = 0
    /// Nothing went out with the link up.
    public var failed = 0
    /// Frames that started late because the previous one overran.
    public var overruns = 0
    public var nextFrameAt: Date?

    public init() {}

    public var isRunning: Bool {
        switch state {
        case .waiting, .running, .paused: true
        case .idle, .finished: false
        }
    }
}

/// Runs a timelapse through the sequencer's frame queue on an injected clock
/// (architecture doc § Intervalometer rules): start-to-start intervals, overruns start
/// the next frame at once, frames wait for *shutter ready* (at most interval
/// + 5 s) on brands with a shutter ack, frames are missed while the link is
/// down, and the run stops after 3 consecutive failures with the link up.
public actor Intervalometer<C: Clock> where C.Duration == Duration {
    public static var maximumConsecutiveFailures: Int { 3 }

    private let sequencer: ShotSequencer<C>
    private let clock: C
    private let now: @Sendable () -> Date
    private let confirmsShots: Bool
    private var snapshot = IntervalometerSnapshot()
    private let updates = Broadcaster<IntervalometerSnapshot>(replayLast: true)
    private var run: Task<Void, Never>?
    private var linkReady = true
    private var consecutiveFailures = 0

    public init(sequencer: ShotSequencer<C>, clock: C, now: @escaping @Sendable () -> Date = { Date() }) {
        self.sequencer = sequencer
        self.clock = clock
        self.now = now
        self.confirmsShots = ShotScript.confirmsShutter(sequencer.driver.shotScript.shootFromFocus
            + sequencer.driver.shotScript.shootWithoutFocus)
        updates.yield(snapshot)
    }

    public nonisolated func snapshots() -> AsyncStream<IntervalometerSnapshot> {
        updates.stream()
    }

    public func currentSnapshot() -> IntervalometerSnapshot { snapshot }

    public func start(_ plan: IntervalometerPlan) {
        guard !snapshot.isRunning else { return }
        consecutiveFailures = 0
        snapshot = IntervalometerSnapshot()
        snapshot.plan = plan
        let firstAt = clock.now.advanced(by: plan.initialWait)
        if plan.initialWait > .zero {
            snapshot.state = .waiting(until: now().addingTimeInterval(plan.initialWaitSeconds))
        } else {
            snapshot.state = linkReady ? .running : .paused
        }
        publish()
        run = Task { [weak self] in await self?.loop(plan, firstAt: firstAt) }
    }

    /// Stops the run. A bulb frame that is open closes at once instead of
    /// holding for the rest of its exposure.
    public func stop() async {
        guard snapshot.isRunning else { return }
        run?.cancel()
        run = nil
        end(.stopped)
        await sequencer.cancelFrameHold()
    }

    public func linkLost() {
        linkReady = false
        if snapshot.state == .running {
            snapshot.state = .paused
            publish()
        }
    }

    public func linkRestored() {
        linkReady = true
        if snapshot.state == .paused {
            snapshot.state = .running
            publish()
        }
    }

    /// Waits for the run to end. For tests.
    public func finished() async {
        await run?.value
    }

    // MARK: Private

    private func loop(_ plan: IntervalometerPlan, firstAt: C.Instant) async {
        var next = firstAt
        do {
            try await clock.sleep(until: next, tolerance: nil)
        } catch {
            return
        }
        if case .waiting = snapshot.state {
            snapshot.state = linkReady ? .running : .paused
        }
        while !Task.isCancelled {
            if let total = plan.frames, snapshot.frame >= total {
                end(.completed)
                return
            }
            snapshot.frame += 1
            next = next.advanced(by: plan.interval)
            snapshot.nextFrameAt = now().addingTimeInterval(Double(clock.now.duration(to: next).components.seconds))
            publish()

            if linkReady {
                let result = await sequencer.frame(
                    focus: plan.focusEachFrame, exposure: plan.exposure,
                    readyTimeout: confirmsShots ? plan.interval + .seconds(5) : nil)
                guard !Task.isCancelled else { return }
                record(result)
                if consecutiveFailures >= Self.maximumConsecutiveFailures {
                    end(.failures)
                    return
                }
            } else {
                snapshot.missed += 1
                publish()
            }

            if let total = plan.frames, snapshot.frame >= total {
                end(.completed)
                return
            }
            if clock.now >= next {
                // Overrun: the next frame starts at once.
                snapshot.overruns += 1
                next = clock.now
                publish()
                continue
            }
            do {
                try await clock.sleep(until: next, tolerance: nil)
            } catch {
                return
            }
        }
    }

    private func record(_ result: ShotResult) {
        if result.wasSent { snapshot.sent += 1 }
        if result.isConfirmed { snapshot.confirmed += 1 }
        switch result {
        case .failed(.transport(.disconnected)), .unconfirmed(.linkLost):
            // The link went down under the frame: missed, not failed.
            if case .unconfirmed = result {} else { snapshot.missed += 1 }
            consecutiveFailures = 0
        case .failed:
            if linkReady {
                snapshot.failed += 1
                consecutiveFailures += 1
            } else {
                snapshot.missed += 1
            }
        default:
            consecutiveFailures = 0
        }
        publish()
    }

    private func end(_ reason: IntervalometerEnd) {
        snapshot.state = .finished(reason)
        snapshot.nextFrameAt = nil
        publish()
    }

    private func publish() {
        updates.yield(snapshot)
    }
}
