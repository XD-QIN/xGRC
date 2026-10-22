import CameraKit
import Foundation
import Persistence
@testable import SessionKit
import SharedState
import Testing

/// product spec § Dynamic Island / Live Activity: update and alert rules.
@Suite("Live Activity planner")
struct ActivityPlannerTests {
    let t0 = Date(timeIntervalSince1970: 1_792_069_509)

    private func state(sent: Int = 0, geotag: TileState.Geotag = .tagging, link: TileState.Link = .connected,
                       timelapse: Bool = false) -> ActivityState {
        ActivityState(cameraName: "α7C II", link: link, geotag: geotag, confirmed: sent, sent: sent,
                      canShoot: true, timelapseRunning: timelapse)
    }

    @Test("Status changes go out at once; counter changes at most every 10 s")
    func throttle() {
        var planner = ActivityPlanner()
        planner.started(at: t0)
        #expect(planner.offer(state(), now: t0) != nil)
        #expect(planner.offer(state(), now: t0.addingTimeInterval(1)) == nil)

        #expect(planner.offer(state(sent: 1), now: t0.addingTimeInterval(2)) == nil)
        #expect(planner.nextFlush == t0.addingTimeInterval(10))
        #expect(planner.flush(now: t0.addingTimeInterval(5)) == nil)
        #expect(planner.flush(now: t0.addingTimeInterval(10))?.state.sent == 1)

        #expect(planner.offer(state(sent: 1, link: .off), now: t0.addingTimeInterval(11)) != nil)
    }

    @Test("Stale after a minute while geotagging, else after the auto-disconnect time")
    func staleDate() {
        var planner = ActivityPlanner()
        planner.idleStaleAfter = ActivityPlanner.idleStaleAfter(autoDisconnectMinutes: 15)
        #expect(planner.offer(state(), now: t0)?.staleDate == t0.addingTimeInterval(60))
        #expect(planner.offer(state(geotag: .off), now: t0.addingTimeInterval(1))?.staleDate
                == t0.addingTimeInterval(1 + 15 * 60))
        var bulb = state(geotag: .off)
        bulb.bulbEnds = t0.addingTimeInterval(1800)
        #expect(planner.offer(bulb, now: t0.addingTimeInterval(2))?.staleDate == t0.addingTimeInterval(1800 + 15 * 60))
        #expect(ActivityPlanner.idleStaleAfter(autoDisconnectMinutes: 0) == 8 * 3600)
    }

    @Test("A state back to what is shown drops the throttled one")
    func throttledThenBack() {
        var planner = ActivityPlanner()
        planner.started(at: t0)
        var five = state()
        five.accuracy = 5
        var eight = state()
        eight.accuracy = 8
        #expect(planner.offer(five, now: t0) != nil)
        #expect(planner.offer(eight, now: t0.addingTimeInterval(1)) == nil)
        #expect(planner.offer(five, now: t0.addingTimeInterval(2)) == nil)
        #expect(planner.flush(now: t0.addingTimeInterval(10)) == nil)
    }

    @Test("Alerts on a countdown release and on failures, never per timelapse frame")
    func alerts() {
        var planner = ActivityPlanner()
        _ = planner.offer(state(), now: t0)
        let ok = ShotResult.acknowledged(focusLatency: nil, shutterLatency: .milliseconds(80))
        #expect(planner.offer(state(sent: 1), event: .shotFinished(ok, delayed: false),
                              now: t0.addingTimeInterval(1))?.alert == nil)
        #expect(planner.offer(state(sent: 2), event: .shotFinished(ok, delayed: true),
                              now: t0.addingTimeInterval(2))?.alert == .released(.taken))
        #expect(planner.offer(state(sent: 3), event: .shotFinished(.unconfirmed(.shutterTimedOut), delayed: false),
                              now: t0.addingTimeInterval(3))?.alert == .shotFailed(.notConfirmed))
        #expect(planner.offer(state(sent: 4, timelapse: true),
                              event: .shotFinished(.unconfirmed(.shutterTimedOut), delayed: false),
                              now: t0.addingTimeInterval(4))?.alert == nil)
        // The next frame inside 10 s is only a counter change: it waits for the throttle.
        #expect(planner.offer(state(sent: 5, timelapse: true),
                              event: .shotFinished(.unconfirmed(.shutterTimedOut), delayed: false),
                              now: t0.addingTimeInterval(4.5)) == nil)
        #expect(planner.offer(state(geotag: .failed), event: .geotagFailed("Location off"),
                              now: t0.addingTimeInterval(5))?.alert == .geotagFailed("Location off"))
    }

    @Test("A new activity is due before the 8-hour limit")
    func restart() {
        var planner = ActivityPlanner()
        #expect(!planner.needsRestart(now: t0))
        planner.started(at: t0)
        #expect(!planner.needsRestart(now: t0.addingTimeInterval(7 * 3600)))
        #expect(planner.needsRestart(now: t0.addingTimeInterval(7 * 3600 + 55 * 60)))
    }

    @Test("The activity state follows the session, shutter and brand")
    func mapping() {
        var session = SessionSnapshot()
        session.link = .ready
        var shutter = ShutterSnapshot()
        shutter.phase = .countdown(ends: t0, total: .seconds(10))
        shutter.lastResult = .assumed(heldFor: .milliseconds(200))
        let state = ActivityState(session: session, geotag: GeotagSnapshot(), shutter: shutter,
                                  timelapseRunning: false, mode: .remoteAndGeotag, backgroundShooting: true)
        #expect(state.canShoot && state.countdownSeconds == 10 && state.lastShot == .sent)
        let noBackground = ActivityState(session: session, geotag: GeotagSnapshot(), shutter: shutter,
                                         timelapseRunning: false, mode: .remoteAndGeotag, backgroundShooting: false)
        #expect(!noBackground.canShoot)
        let geotagOnly = ActivityState(session: session, geotag: GeotagSnapshot(), shutter: shutter,
                                       timelapseRunning: false, mode: .geotagOnly, backgroundShooting: true)
        #expect(!geotagOnly.canShoot)

        shutter.phase = .bulbOpen(since: t0, ends: t0.addingTimeInterval(30))
        let bulb = ActivityState(session: session, geotag: GeotagSnapshot(), shutter: shutter,
                                 timelapseRunning: false, mode: .remoteAndGeotag, backgroundShooting: true)
        #expect(bulb.bulbEnds == t0.addingTimeInterval(30) && bulb.bulbSeconds == 30 && bulb.countdownEnds == nil)
    }

    @Test("The content stays well under the 4 KB limit")
    func size() throws {
        let full = ActivityState(cameraName: String(repeating: "W", count: 64), link: .connected, geotag: .tagging,
                                 accuracy: 4.2, lastPushAt: t0, confirmed: 9999, sent: 9999, countdownEnds: t0,
                                 countdownSeconds: 60, bulbEnds: t0, bulbSeconds: 600, canShoot: true, timelapseRunning: true, lastShot: .notConfirmed)
        #expect(try JSONEncoder().encode(full).count < 1024)
    }
}
