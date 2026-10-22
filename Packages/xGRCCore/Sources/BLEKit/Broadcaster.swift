import Foundation

/// Fans one sequence of values out to any number of `AsyncStream`s.
/// Each call to `stream()` gets every value yielded after it subscribed.
/// Values are handed out under the lock, so every stream sees them in the
/// order they were yielded, and a replay is never overtaken by a newer value.
public final class Broadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var isFinished = false
    /// The last value, replayed to new subscribers when `replayLast` is set.
    private var last: Element?
    private let replayLast: Bool

    public init(replayLast: Bool = false) {
        self.replayLast = replayLast
    }

    public func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            if isFinished {
                lock.unlock()
                continuation.finish()
                return
            }
            continuations[id] = continuation
            if replayLast, let last { continuation.yield(last) }
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    public func yield(_ value: Element) {
        // `yield` only buffers; it never calls back into this class.
        lock.lock()
        last = value
        for continuation in continuations.values { continuation.yield(value) }
        lock.unlock()
    }

    public func finish() {
        lock.lock()
        isFinished = true
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets { continuation.finish() }
    }
}
