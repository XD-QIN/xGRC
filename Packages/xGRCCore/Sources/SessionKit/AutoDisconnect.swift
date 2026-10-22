import Foundation

/// Why a session ended by itself.
public enum SessionEndReason: Hashable, Sendable {
    /// Connected, but nothing was done with the camera for the timeout.
    case idle(minutes: Int)
    /// The camera could not be reached for the timeout.
    case unreachable(minutes: Int)
    /// The link dropped with Settings › Auto reconnect off.
    case linkLost
}

/// Auto disconnect (Settings › Auto disconnect, 15 minutes by default):
/// the session ends after the timeout with no activity while connected, or
/// with no link at all. Geotagging, a timelapse, a countdown or an open bulb
/// count as activity for as long as they run, so the idle time starts when
/// they end. Ending cancels the pending connect, which frees the camera for
/// another device and saves both batteries.
public struct AutoDisconnect: Sendable {
    /// `nil` = never.
    public let timeout: Duration?
    public let minutes: Int
    public private(set) var lastActivity: ContinuousClock.Instant
    public private(set) var unreachableSince: ContinuousClock.Instant?

    public init(minutes: Int, unit: Duration = .seconds(60), now: ContinuousClock.Instant) {
        self.minutes = max(minutes, 0)
        timeout = minutes > 0 ? unit * minutes : nil
        lastActivity = now
        unreachableSince = now
    }

    /// The user did something with the camera (a shot, an intent, a start).
    public mutating func activity(now: ContinuousClock.Instant) {
        lastActivity = now
    }

    public mutating func link(_ state: LinkState, now: ContinuousClock.Instant) {
        switch state {
        case .ready:
            if unreachableSince != nil { lastActivity = now }
            unreachableSince = nil
        case .ended:
            break
        default:
            if unreachableSince == nil { unreachableSince = now }
        }
    }

    /// Whether to end the session now. `busy`: something is running that
    /// counts as activity.
    public mutating func check(now: ContinuousClock.Instant, busy: Bool) -> SessionEndReason? {
        guard let timeout else { return nil }
        if let since = unreachableSince {
            return since.duration(to: now) >= timeout ? .unreachable(minutes: minutes) : nil
        }
        if busy {
            lastActivity = now
            return nil
        }
        return lastActivity.duration(to: now) >= timeout ? .idle(minutes: minutes) : nil
    }
}
