import ActivityKit
import Foundation
import SessionKit
import SharedState

/// Owns the session's Live Activity (product spec § Dynamic Island / Live
/// Activity). `ActivityPlanner` decides what to send and when; this class
/// only talks to ActivityKit.
@MainActor
final class LiveActivityController {
    private var activity: Activity<SessionActivityAttributes>?
    private var planner = ActivityPlanner()
    private var flushTask: Task<Void, Never>?
    private var latest: SharedState.ActivityState?
    /// The user ended the session: no activity is requested again until the
    /// session's end reaches `update`, so a late snapshot cannot bring it back.
    private var held = false

    /// Without geotagging, how long the activity stays fresh with no update
    /// (Settings › Auto disconnect), so a killed app leaves no live-looking one.
    var idleStaleAfter: TimeInterval {
        get { planner.idleStaleAfter }
        set { planner.idleStaleAfter = newValue }
    }

    /// - Parameters:
    ///   - enabled: Settings › Live Activity.
    ///   - appActive: an activity can only be requested from the foreground.
    func update(_ state: SharedState.ActivityState, event: ActivityEvent?, enabled: Bool, appActive: Bool) {
        latest = state
        if state.link == .noSession { held = false }
        guard enabled, state.link != .noSession, !held else {
            end()
            return
        }
        if activity == nil || planner.needsRestart(now: .now) {
            // Re-requested on the next foreground visit after the 8-hour limit.
            guard appActive, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            request(state)
            return
        }
        if let update = planner.offer(state, event: event, now: .now) { send(update) }
        scheduleFlush()
    }

    /// A new session starts (open, pair, retry): an *End session* before it
    /// no longer holds the activity back, even if no session was there to
    /// publish its end.
    func resume() {
        held = false
    }

    /// *End session*: the activity goes now, before the camera is released.
    /// Every xGRC activity ends, not only the tracked one, so none is left in
    /// the Dynamic Island if a reference was lost.
    func endNow() {
        held = true
        end()
        for other in Activity<SessionActivityAttributes>.activities {
            nonisolated(unsafe) let ending = other
            Task { await ending.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Ends activities left over from a run of the app that stopped without
    /// ending them (force quit, crash, a debug stop). Call at launch.
    func endStale() {
        for stale in Activity<SessionActivityAttributes>.activities where stale.id != activity?.id {
            nonisolated(unsafe) let ending = stale
            Task { await ending.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// The app is terminating: every activity ends with it. Waits briefly,
    /// since nothing runs after this returns.
    nonisolated static func endAllBeforeExit() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in Activity<SessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    func end() {
        flushTask?.cancel()
        flushTask = nil
        planner.ended()
        guard let activity else { return }
        self.activity = nil
        let final = ActivityContent(state: latest ?? activity.content.state, staleDate: nil)
        // `Activity` is safe to use from any thread but is not marked
        // `Sendable`, so each hand-off to its async methods opts out here.
        nonisolated(unsafe) let ending = activity
        Task { await ending.end(final, dismissalPolicy: .immediate) }
    }

    // MARK: Private

    private func request(_ state: SharedState.ActivityState) {
        let previous = activity
        let now = Date()
        planner.started(at: now)
        guard let first = planner.offer(state, now: now) else { return }
        do {
            activity = try Activity.request(attributes: SessionActivityAttributes(startedAt: now),
                                            content: ActivityContent(state: first.state, staleDate: first.staleDate),
                                            pushType: nil)
        } catch {
            activity = nil
            planner.ended()
        }
        if let previous {
            nonisolated(unsafe) let ending = previous
            Task { await ending.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func send(_ update: ActivityUpdate) {
        guard let activity else { return }
        let content = ActivityContent(state: update.state, staleDate: update.staleDate)
        let alert = update.alert.map(Self.alertConfiguration)
        nonisolated(unsafe) let updating = activity
        Task { await updating.update(content, alertConfiguration: alert) }
    }

    private func scheduleFlush() {
        guard let next = planner.nextFlush else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            if let update = self.planner.flush(now: .now) { self.send(update) }
        }
    }

    /// Alerts light the Island or the Lock Screen: only on a countdown release
    /// and on failures.
    private static func alertConfiguration(_ alert: ActivityAlert) -> AlertConfiguration {
        switch alert {
        case .released(let shot):
            AlertConfiguration(title: "Release delay", body: "\(shotText(shot))", sound: .default)
        case .shotFailed(let shot):
            AlertConfiguration(title: "Shot not confirmed", body: "\(shotText(shot))", sound: .default)
        case .geotagFailed(let reason):
            AlertConfiguration(title: "Geotagging stopped", body: "\(reason)", sound: .default)
        }
    }

    static func shotText(_ shot: SharedState.ActivityState.Shot) -> String {
        switch shot {
        case .taken: String(localized: "Taken. The camera confirmed it.")
        case .sent: String(localized: "Sent. This camera does not confirm shots.")
        case .notConfirmed: String(localized: "Sent, not confirmed.")
        case .failed: String(localized: "Nothing was sent to the camera.")
        }
    }
}
