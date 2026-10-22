# Phase 3 — Watch polish

Companion to [plan § Phase 3](10-14-26_phased-plan-04.md#phase-3--watch-polish) and the [product spec](10-14-26_product-spec-01.md), [architecture doc](10-14-26_architecture-02.md) and [protocol reference](10-14-26_ble-protocol-reference-03.md). This file records what Phase 3 built and the device tests it adds to the [Phase 6 device test pass](10-14-26_phased-plan-04.md#phase-6--device-test-pass).

**Status (2026-10-15):** code complete. The package has 85 tests, all passing on Linux with Swift 6.1; 24 of them are new in this phase (the other 6 cover the Phase 4 Live Activity planner). `project.yml` generates with XcodeGen 2.46. The watch views, the widget and the intents need the Apple SDK and are first compiled at the start of Phase 6.

---

## What was built

| Piece | Where | What it does |
|---|---|---|
| Mode setting | `SessionMode` and `AppSettings.sessionMode` in `Persistence`; `SessionCoordinator.setMode`; `ModePicker` and `AppSettingsView` in `SettingsView.swift` | **Remote + Geotag**, **Remote only** or **Geotag only**. Chosen at first launch, changed in Settings (the session's Settings page or *Settings* on the camera list), saved in the watch's settings file. A change applies to the running session at once |
| Mode in the session | `CameraSession.setFeatures`, `SonyDriver.setFeatures`, `SessionCoordinator` | *Remote only* never starts location. *Geotag only* starts geotagging as soon as the camera is ready, ignores shutter input, stops a running timelapse, and connects with *Bluetooth Rmt Ctrl* off: the Sony driver then needs only `DD11` and tolerates the remote characteristics being absent or refusing notifications |
| Pages by mode | `SessionView.swift` | Shutter only when the mode uses the remote, Geotag only when it uses location, Settings always. Changing the mode keeps the current page if it is still shown |
| Release delay | `ShotSequencer` (`.countdown` phase, `releaseDelay`), `ReleaseDelayView`, `ShutterButton` | Off or 1–60 s on the Digital Crown. Double tap or Shoot starts the countdown with focus held; at zero the shot fires; a tap or Shoot cancels; leaving the app cancels. One haptic on release, and a local notification if the wrist is down |
| Intervalometer | `Intervalometer` actor in `SessionKit`, `IntervalometerSheet` and `IntervalometerStatus` | the spec's rules: start-to-start intervals, an overrun starts the next frame at once, frames wait for *shutter ready* (up to interval + 5 s), frames are *missed* while the link is down, 3 failures in a row with the link up stop the run, above 1 s the frame runs as bulb, no release delay. The last plan is saved and offered next time |
| Crown settings | `CrownRow` and `CrownChoice` in `SettingsView.swift` | Every setting with a value (Mode, Release delay, Focus hold, Send location, the timelapse values) opens a screen where the Digital Crown scrolls through the values; saved on leaving the screen. VoiceOver adjusts it by swiping up and down |
| Auto disconnect | `AutoDisconnect` in `SessionKit`, `SessionCoordinator`, `ConnectionSettings` | Ends the session after 15 minutes (Never, 5–60 on the Crown) connected with nothing done, or without reaching the camera. Geotagging, a timelapse, a countdown or bulb count as use while they run. The camera list then says why, with a notification if the app is not on screen |
| Onboarding | `OnboardingView.swift` | Mode choice, *Return to Clock › After 1 hour*, don't force-quit. Shown at first launch and from *Show tips again* in Settings |
| Accessibility | `ShutterButton` | Actions Focus, Start/Stop bulb and Cancel countdown (Shoot is the button's own action), state announcements, Digital Crown value adjustable by VoiceOver |
| Rescan on disconnect | `CameraSession`, `xGRCWatchApp` | After a disconnect, a foreground scan runs alongside the pending connect. If the camera is seen advertising for 2 s while the pending connect has not completed, a fresh connect replaces it, once per disconnect |
| Liveness and notices | `CameraSession.checkLiveness`, `SessionNotice` | On wrist raise after more than 60 s idle, one RSSI read with a 3 s timeout before trusting *Connected*. The reduced-range and wake-up-budget banners show under the link line, with a Retry button when another device holds the camera |
| Smart Stack tile | `ShutterTile.swift` (widget), `TileState` in `Persistence`, `AppModel.updateTile` | Camera name and link dot, the geotag line (*Tagging* with the session timer, *Waiting for GPS*, or *Last push* with its age once pushes stop, red after 30 minutes), and a Shoot button on watchOS 11+ while connected in a mode that uses the remote. Double Tap is declared on it only while a session runs |
| Shoot and other intents | `Apps/Shared/CameraIntents.swift`, `AppShortcuts.swift`, `SessionCoordinator.shootFromIntent` / `focusFromIntent` | *Shoot*, *Focus*, *Start geotagging*, *Stop geotagging*, with Siri phrases. Shoot focuses, fires and answers within 8 s: taken (confirmed), sent, sent not confirmed, or still running. With no session or no link the intent asks to continue in xGRC |
| Shoot control | `ShootControl` (watchOS 26+) | The watch app's own control for Control Center, the Smart Stack and the Ultra Action Button. Before watchOS 26 the Action Button runs the Shoot shortcut |
| Firmware change | `LinkState.firmwareChanged` | A missing characteristic after a reconnect says "The camera's firmware changed. Forget and pair again." |

---

## Decisions and defaults

1. **The mode is per watch, not per camera.** The request was one setting the app remembers; a per-camera mode can come later if bodies need different modes. The default is *Remote + Geotag*, which keeps Phases 1 and 2 behaving as before.
2. **Geotag only replaces the Sony Remote-or-Geotag modal for now.** The spec keys that modal on model codes nobody has verified yet. Until Phase 6 records them, Sony users with a body older than the α7 IV pick *Geotag only* and turn *Bluetooth Rmt Ctrl* off; the Geotag page says so.
3. **Wrist down is not leaving the app.** Countdowns, bulb and timelapses keep running while the scene is inactive. Only the background phase (another app or the watch face) releases every button.
4. **Timelapse frames skip the release delay** and never count down, as the spec's intervalometer rules say.
5. **A timelapse result with the wrist down** plays no haptic (watchOS drops it) and posts a local notification instead.
6. **The tile reloads only when it would look different.** Widget reloads from the background are budgeted, and pushes arrive every few seconds, so the tile shows *Tagging* with the session timer rather than the push age while pushes flow. The push age appears once pushes stop, when it no longer changes, and a scheduled timeline entry turns it red after 30 minutes.
7. **One App Group file.** The app writes `TileState.json` into `group.<bundle prefix>`; nothing else is shared with the widget. Set the App Group on both targets when signing (Phase 6 step 1).
8. **Intents use `ForegroundContinuableIntent` on every watchOS version for now.** The spec asks for background plus dynamic-foreground modes on watchOS 26+. Which process runs a widget button's intent is checked on the watch in Phase 6 (test 10). If it runs in the widget extension, the intent opens xGRC instead of shooting.
9. **Intents apply the release delay only while geotagging,** as the spec says: then the app keeps running through the countdown. Otherwise they fire at once.
10. **Every watch setting with a value is set with the Digital Crown** (asked for on 2026-10-15). Tapping the row opens a screen with the value large and its neighbours above and below; the Crown steps through the values with a detent per step, a tap on a neighbour steps to it, and the choice is saved on leaving the screen, so turning past a mode never applies it. This covers Mode, Release delay, Focus hold, the geotag interval and the four timelapse values. On/off settings stay toggles.
11. **Auto disconnect counts running work as use** (asked for on 2026-10-15, 15 minutes by default, user-selectable). A geotag session or timelapse never ends for being idle; the idle time starts when it stops. Losing the camera for the whole time ends the session even while geotagging, because nothing reaches the camera, and frees it for another device.

---

## Device tests (run in Phase 6)

Record results in `docs/support/<brand>-<model>.md` (template in [Phase 1 doc](10-15-26_phase-1-watch-remote-01.md#support-record-template)) and every problem in the pass's issue list.

| # | Test | How | Record |
|---|---|---|---|
| 1 | Remote only | Pick it, open a session, shoot | No location prompt, no Geotag page, no `DD30`/`DD31` writes in the transcript |
| 2 | Geotag only | Pick it, turn *Bluetooth Rmt Ctrl* off on the camera, open a session | Geotagging starts by itself; photos are tagged; no Shutter page |
| 3 | Switch mid-session | Change the mode from the session's Settings page | Pages change at once; geotag stops in *Remote only* and starts in *Geotag only* |
| 4 | Remembered | Pick a mode, force-quit, relaunch | The same mode, and onboarding does not show again |
| 5 | Release delay | 10 s delay, Double Tap, wrist up; then again with the wrist down | One haptic at release; the notification with the wrist down; a tap cancels |
| 6 | Timelapse | 200 frames at 5 s on a tripod | 200 acknowledged frames; no abort on a transient disconnect; missed frames counted |
| 7 | Bulb timelapse | 10 frames, shutter open 4 s, camera in BULB | Each frame's exposure is about 4 s |
| 8 | Rescan | Turn the camera off and on during a session | Reconnect time; whether the rescan or the pending connect won (transcript) |
| 9 | Accessibility | VoiceOver and AssistiveTouch through the shutter actions and the Digital Crown | Every action works |
| 10 | Tile Shoot | Add the tile to the Smart Stack, connect, leave xGRC, tap Shoot on the tile; then Double Tap with the tile selected | The shot fires without opening xGRC (or xGRC opens: note which); the intent's line; Double Tap does nothing with no session |
| 11 | Tile state | Start and stop geotagging, walk out of range, return | The tile changes within a few seconds each time; *Last push* turns red after 30 minutes without pushes |
| 12 | Siri and Action Button | "Shoot with xGRC"; on an Ultra, bind the Action Button (Shoot shortcut, or the Shoot control on watchOS 26) | Each fires within 8 s and says taken, sent or not confirmed |
| 13 | Crown settings | Change Mode, Release delay and a timelapse value with the Crown; turn past a value and back; leave without turning | One detent per value; only the value shown when leaving is saved; leaving without turning changes nothing |
| 14 | Auto disconnect | Set 5 minutes; leave the session alone; then turn the camera off during a geotag session | The session ends after 5 minutes each time; the camera list says why; the camera can be used from another device right after |

### Phase 6 bars for this part

- [ ] All three modes work on the real camera and the choice survives a relaunch
- [ ] A 200-frame timelapse completes
- [ ] VoiceOver and AssistiveTouch pass
- [ ] The tile, Siri and the Action Button each take a photo
- [ ] Auto disconnect ends an idle session and an unreachable one

---

## Known gaps

- **Brand-specific onboarding tips** wait for the Phase 5 drivers.
- **The Remote-or-Geotag modal** waits for verified Sony model codes (decision 2).
