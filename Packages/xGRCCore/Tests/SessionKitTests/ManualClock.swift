import Foundation
@testable import SessionKit
import Testing

/// A clock that only moves when the test advances it.
final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [UUID: Sleeper] = [:]

    var now: Instant {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if deadline <= current || Task.isCancelled {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let sleeper = sleepers.removeValue(forKey: id)
            lock.unlock()
            sleeper?.continuation.resume()
        }
        try Task.checkCancellation()
    }

    /// Moves time forward and wakes every sleeper whose deadline has passed.
    func advance(by duration: Duration) async {
        let due = lock.withLock {
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.value.deadline <= current }
            for id in due.keys { sleepers[id] = nil }
            return due
        }
        for sleeper in due.values.sorted(by: { $0.deadline < $1.deadline }) {
            sleeper.continuation.resume()
        }
        await settle()
    }

    /// Number of tasks currently sleeping on this clock.
    var sleeperCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.count
    }
}

/// Lets other tasks run for a moment of real time.
func settle() async {
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(5))
    for _ in 0..<20 { await Task.yield() }
}

/// Polls `condition` for up to two seconds of real time.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

extension ManualClock {
    /// Advances once at least `sleepers` tasks are asleep on this clock.
    /// A task that computes its deadline from `now` only when it reaches
    /// its sleep (a held press, a frame's bulb) would otherwise miss an
    /// advance that came first, and the test would hang or flake.
    func advance(by duration: Duration, afterSleepers sleepers: Int) async {
        let ready = await eventually { self.sleeperCount >= sleepers }
        if !ready { Issue.record("expected \(sleepers) sleepers before advancing, found \(sleeperCount)") }
        await advance(by: duration)
    }
}

/// `idle()` with a limit of two seconds of real time, so a hang fails the
/// test instead of stalling the whole run.
func awaitIdle<C>(_ sequencer: ShotSequencer<C>, sourceLocation: SourceLocation = #_sourceLocation) async {
    let finished = await value(of: Task { await sequencer.idle(); return true }, within: .seconds(2))
    if finished == nil { Issue.record("the sequencer did not go idle", sourceLocation: sourceLocation) }
}
