import CameraKit
import Foundation
import Persistence
import SharedState

extension ActivityState {
    /// The Live Activity's view of the running session.
    public init(session: SessionSnapshot, geotag: GeotagSnapshot, shutter: ShutterSnapshot,
                timelapseRunning: Bool, mode: SessionMode, backgroundShooting: Bool) {
        let tile = TileState(session: session, geotag: geotag, mode: mode, backgroundShooting: backgroundShooting)
        var countdownEnds: Date?
        var countdownSeconds: Int?
        var bulbEnds: Date?
        var bulbSeconds: Int?
        switch shutter.phase {
        case .countdown(let ends, let total):
            countdownEnds = ends
            countdownSeconds = Int(total.components.seconds)
        case .bulbOpen(let since, let ends):
            bulbEnds = ends
            bulbSeconds = Int(ends.timeIntervalSince(since).rounded())
        default:
            break
        }
        self.init(cameraName: session.camera?.name ?? "",
                  link: tile.link,
                  geotag: tile.geotag,
                  accuracy: geotag.isActive ? geotag.fix?.horizontalAccuracy : nil,
                  lastPushAt: geotag.lastPushAt,
                  confirmed: shutter.confirmed,
                  sent: shutter.sent,
                  countdownEnds: countdownEnds,
                  countdownSeconds: countdownSeconds,
                  bulbEnds: bulbEnds,
                  bulbSeconds: bulbSeconds,
                  canShoot: tile.canShoot,
                  timelapseRunning: timelapseRunning,
                  lastShot: shutter.lastResult.map(ActivityState.Shot.init))
    }
}

extension ActivityState.Shot {
    public init(_ result: ShotResult) {
        switch result {
        case .acknowledged: self = .taken
        case .assumed: self = .sent
        case .unconfirmed: self = .notConfirmed
        case .cancelled, .failed: self = .failed
        }
    }
}

/// Something worth lighting the Island or the Lock Screen for.
public enum ActivityAlert: Hashable, Sendable {
    /// A release-delay countdown fired.
    case released(ActivityState.Shot)
    /// A shot did not go out, or went out without the camera's confirmation.
    case shotFailed(ActivityState.Shot)
    case geotagFailed(String)
}

/// One Live Activity update: the content, when the system should grey it out
/// if no update follows, and an alert if the change deserves one.
public struct ActivityUpdate: Hashable, Sendable {
    public var state: ActivityState
    public var staleDate: Date?
    public var alert: ActivityAlert?
}

/// What happened, as the app saw it, alongside the new state.
public enum ActivityEvent: Hashable, Sendable {
    case shotFinished(ShotResult, delayed: Bool)
    case geotagFailed(String)
}

/// When to update the Live Activity (product spec § Dynamic Island / Live Activity):
/// status changes go out at once, counter and push changes at most every
/// 10 s; alerts only on a countdown release and on failures, never per
/// timelapse frame; always a `staleDate`, so the system greys the activity
/// out if updates stop (the app was killed): a minute while geotagging,
/// else the auto-disconnect time; a fresh activity before the 8-hour limit.
public struct ActivityPlanner: Sendable {
    public static let minimumInterval: TimeInterval = 10
    /// Updates are expected every few seconds while geotagging.
    public static let staleAfter: TimeInterval = 60
    /// The system ends an activity at 8 h; it is replaced a little before.
    public static let restartAfter: TimeInterval = 8 * 3600 - 10 * 60
    /// The system's own limit, the stale date when nothing ends a session.
    public static let longestActivity: TimeInterval = 8 * 3600

    /// Without geotagging, how long the activity stays fresh with no update
    /// after the last countdown or bulb ends: by then auto disconnect would
    /// have ended the session.
    public var idleStaleAfter: TimeInterval = ActivityPlanner.longestActivity

    /// `idleStaleAfter` for Settings › Auto disconnect (0 = never).
    public static func idleStaleAfter(autoDisconnectMinutes minutes: Int) -> TimeInterval {
        minutes > 0 ? TimeInterval(minutes) * 60 : longestActivity
    }

    public private(set) var startedAt: Date?
    private var lastSent: ActivityState?
    private var lastSentAt: Date?
    private var pending: ActivityState?

    public init() {}

    /// Call when a new activity was requested.
    public mutating func started(at date: Date) {
        startedAt = date
        lastSent = nil
        lastSentAt = nil
        pending = nil
    }

    public mutating func ended() {
        startedAt = nil
        lastSent = nil
        lastSentAt = nil
        pending = nil
    }

    /// The update to send now, or `nil` if it waits for the throttle; then
    /// `nextFlush` says when to call `flush`.
    public mutating func offer(_ state: ActivityState, event: ActivityEvent? = nil, now: Date) -> ActivityUpdate? {
        let alert = event.flatMap { Self.alert(for: $0, timelapseRunning: state.timelapseRunning) }
        if let lastSent, state == lastSent, alert == nil {
            // Back to what is shown: an older throttled state must not follow.
            pending = nil
            return nil
        }
        // A timelapse frame's result is only a counter change: throttled too.
        let throttled = alert == nil && (event == nil || state.timelapseRunning)
            && lastSent.map { $0.sameStatus(as: state) } == true
            && lastSentAt.map { now.timeIntervalSince($0) < Self.minimumInterval } == true
        if throttled {
            pending = state
            return nil
        }
        return send(state, alert: alert, now: now)
    }

    /// The throttled update, once its time has come.
    public mutating func flush(now: Date) -> ActivityUpdate? {
        guard let pending, let next = nextFlush, now >= next else { return nil }
        return send(pending, alert: nil, now: now)
    }

    public var nextFlush: Date? {
        guard pending != nil, let lastSentAt else { return nil }
        return lastSentAt.addingTimeInterval(Self.minimumInterval)
    }

    /// The activity is close to the system's 8-hour limit.
    public func needsRestart(now: Date) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) >= Self.restartAfter
    }

    private mutating func send(_ state: ActivityState, alert: ActivityAlert?, now: Date) -> ActivityUpdate {
        lastSent = state
        lastSentAt = now
        pending = nil
        return ActivityUpdate(state: state, staleDate: staleDate(for: state, now: now), alert: alert)
    }

    private func staleDate(for state: ActivityState, now: Date) -> Date {
        if state.geotag != .off { return now.addingTimeInterval(Self.staleAfter) }
        // A timelapse frame may be far apart; it blocks auto disconnect anyway.
        if state.timelapseRunning { return now.addingTimeInterval(Self.longestActivity) }
        let busyUntil = [state.countdownEnds, state.bulbEnds].compactMap { $0 }.max() ?? now
        return max(now, busyUntil).addingTimeInterval(idleStaleAfter)
    }

    private static func alert(for event: ActivityEvent, timelapseRunning: Bool) -> ActivityAlert? {
        switch event {
        case .geotagFailed(let reason):
            return .geotagFailed(reason)
        case .shotFinished(let result, let delayed):
            if timelapseRunning { return nil }
            if delayed, result != .cancelled { return .released(ActivityState.Shot(result)) }
            switch result {
            case .failed, .unconfirmed: return .shotFailed(ActivityState.Shot(result))
            default: return nil
            }
        }
    }
}
