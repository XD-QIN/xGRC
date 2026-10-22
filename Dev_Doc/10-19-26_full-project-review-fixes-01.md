# Full project review fixes

Date: 2026-10-19.

Three reviewers read the whole project: the core package (`Packages/xGRCCore`, findings C1–C27), the iPhone and iPad app (A1–A26), and the watch app with config, docs and legal (W1–W11, K1, D1–D6, L1; the config finding the watch reviewer called C1 is K1 here). Each finding was checked against the code before it was fixed. The fixed product decisions were not changed. Nothing was built in the cloud (there is no Swift toolchain there). On the Mac, at commit e4da0b6, `swift test` passed all 173 tests (112 + 61) and the xGRC-iOS scheme (iPhone app, watch app and both widgets) built with no errors. The changes have not been installed on the devices yet; the device test checklist below still applies.

Outcomes: **64 fixed** (7 of them also need a device check), **5 merged** into another finding, **3 left for a device check** with no code change, **0 dropped**.

## Core (C1–C27)

| ID | Outcome |
|---|---|
| C1 | Fixed. When Bluetooth is not *poweredOn*, the central drops its transports' links. The session's pending connect then waits for *poweredOn* and connects again. `CoreBluetoothCentral.swift`, `CameraSession.swift` |
| C2 | Fixed. `connect` waits up to a short timeout for a known central state, so a launch restore no longer fails on `.unknown`. An already-connected peripheral is marked connected. `CoreBluetoothCentral.swift`, `CoreBluetoothTransport.swift` |
| C3 | Fixed, needs a device check. After a reconnect, Sony reads FF02 in answer to the close. *Shutter active* means the close opened a new bulb, so it closes once more. Nikon Time cannot report its shutter, so the close goes out and the shutter hint says to check the camera (`ShutterHint.checkBulb`). `ShotSequencer.swift`, both `SessionView.swift` |
| C4 | Fixed. A Sony shutter ack that arrives after the 3 s window now closes the bulb it reveals. For a gesture bulb a background watch does it; an intervalometer frame waits for it. A link loss during that wait leaves the close to the reconnect. `ShotSequencer.swift` |
| C5 | Fixed. *Shoot* from an intent with bulb time set, on a toggling bulb (Sony, Nikon Time), while nothing keeps the app running, throws `SessionError.bulbNeedsApp` ("Bulb time is set. Open xGRC to take a bulb shot."). `SessionCoordinator.swift`, `AppModel.swift` |
| C6 | Fixed. A drop after *Pair again* or *Firmware changed* keeps that state and cancels the OS reconnect once. `CameraSession.swift` |
| C7 | Fixed. A failed `activate()` publishes a *failed* link with a short reason and stops the auto disconnect. *Retry* then works from the snapshot's camera. `SessionCoordinator.swift` |
| C8 | Fixed. `endSession()` chains teardowns, and a new pair or activate waits for the last one. An old teardown can no longer cancel the new link, or its location updates. `SessionCoordinator.swift` |
| C9 | Fixed. Link events are subscribed as soon as the transport exists and passed to the session, so a drop during pairing or registration is not lost. `SessionCoordinator.swift`, `CameraSession.swift` |
| C10 | Fixed. After two refused pushes in a row the geotag status is the new `.cameraNotTagging` ("photos untagged"). A push the driver refuses for lack of a location link enables the link again, at most every 30 s. `GeoTagStreamer.swift`, `SonyDriver.swift`, `AppModel.swift` |
| C11 | Needs a device check, no change. The location-enabled advertisement bit on older Sony bodies (no DD30/DD31) is not confirmed on hardware. Persisting it in `CameraRecord` waits for that check. |
| C12 | Fixed. Peripherals that Core Bluetooth restoration handed back, and that no restored session uses, are cancelled at launch. `CoreBluetoothCentral.swift`, `GATTTransport.swift`, `SessionCoordinator.swift` |
| C13 | Fixed. When registration fails for good: *Rmt Ctrl off* and *unsupported* become a *failed* link that says why; a timeout drops the link and reconnects; only other errors ask to pair again. `CameraSession.swift` |
| C14 | Fixed. `register()` runs one registration at a time; a request that arrives during one runs it once more afterwards. `CameraSession.swift` |
| C15 | Fixed. Every new shot or frame cancels the previous late-ack watcher. `ShotSequencer.swift` |
| C16 | Fixed. `frame()` takes a stop count when it is queued, so it can no longer undo an intervalometer stop. An intent's frame is not stoppable. `ShotSequencer.swift`, `SessionCoordinator.swift` |
| C17 | Fixed, needs a device check. The Sony driver no longer refuses a short write limit; the DD11 packet goes as a long write. The test models a transport that reports 512 with a response. `SonyDriver.swift`, `BluetoothRobustnessTests.swift` |
| C18 | Fixed. The watch's rescan window has its own timer, so it ends even when nothing advertises. `CameraSession.swift` |
| C19 | Fixed. The transcript is a real ring buffer: O(1) per entry once full; `snapshot()` returns entries oldest first. `Transcript.swift` |
| C20 | Fixed. Every error after a successful connect, in pair and in activate, cancels the connection. `SessionCoordinator.swift` |
| C21 | Fixed. `forget()` also ends a session that is still activating for that camera. `SessionCoordinator.swift` |
| C22 | Fixed. When the offered state equals the one shown, a pending throttled update is dropped. `ActivityPlanner.swift` |
| C23 | Fixed. While a bulb may be open, auto disconnect waits and logs why. `SessionCoordinator.swift` |
| C24 | Needs a device check, no change. Whether Ricoh's `02 00` stops a movie or exposure started on the body is not settled by the protocol reference. |
| C25 | Fixed. When a subscription's last listener goes, notifications are turned off on a connected peripheral. `CoreBluetoothTransport.swift` |
| C26 | Fixed. A mode change counts as activity for auto disconnect. `SessionCoordinator.swift` |
| C27 | Fixed. The test doubles gained `dropLink(isReconnecting:)` and `FakeCamera.powerCycle()`. New tests cover a plain drop after pairing, a power cycle during a bulb, and a failed relink. `FakeCamera.swift`, `SimulatedPeripheral.swift`, tests |

## iPhone and iPad app (A1–A26)

| ID | Outcome |
|---|---|
| A1 | Fixed, needs a device check. The screen stays on (`isIdleTimerDisabled`) while a session that uses the remote is open. Leaving the app still releases everything, as before. `AppModel.swift` |
| A2 | Merged into C2, with the failed-activate display from C7. |
| A3 | Fixed. The pairing sheet owns its attempt, *Try again* included: it starts on appear, is cancelled on disappear, and a success closes the sheet. *Cancel* ends only a pairing that is still running. A finished pairing always opens the session. `AddCameraView.swift` (iOS and watch), `AppModel.swift` |
| A4 | Fixed. Every error the app shows has its own sentence; anything unknown says "Something went wrong talking to the camera. Try again." The link and geotag failures use the same short wording (`describeFailure`). `AppModel.swift`, `CameraSession.swift`, `GeoTagStreamer.swift` |
| A5 | Fixed. The Live Activity always has a stale date: 60 s while geotagging, otherwise the auto-disconnect time after the last countdown or bulb, 8 h during a timelapse. The Island hides its shutter when stale. `ActivityPlanner.swift`, `LiveActivityController.swift`, `SessionLiveActivity.swift` |
| A6 | Fixed. A failed Island or control press shows a failure on the activity. A stale Shoot control opens xGRC. `SessionActivity.swift`, `CameraIntents.swift`, `AppModel.swift` |
| A7 | Fixed. Pair, open and retry clear the `held` flag. `LiveActivityController.swift`, `AppModel.swift` |
| A8 | Fixed. Mode and settings changes refresh the tile, the Live Activity and the keep-screen-on state. `AppModel.swift` |
| A9 | Fixed. The iPad detail stack is rebuilt when the sidebar route changes. `RootView.swift` |
| A10 | Merged into C8 (the old teardown no longer stops the new session's location). |
| A11 | Fixed. With Precise Location off, geotagging fails with `.preciseLocationOff` and says how to turn it on. `CoreLocationSource.swift`, `LocationSource.swift`, `GeoTagStreamer.swift`, `AppModel.swift` |
| A12 | Needs a device check, no change. Does *Start geotagging* from Siri, with the app in the background and When-In-Use permission, get fixes? If not, make the intent continue in the foreground. A13 already stops the authorization request from hanging there. |
| A13 | Fixed. If location access is taken away mid-session, the fix stream ends and the streamer says why. In the background, a request that cannot prompt returns at once ("Open xGRC to allow Location."). `CoreLocationSource.swift`, both app delegates, `GeoTagStreamer.swift` |
| A14 | Fixed. Add camera shows "Scan stopped. No camera found." after the 30 s scan. Finishing onboarding restarts the scan. `AppModel.swift`, `AddCameraView.swift` (iOS and watch) |
| A15 | Merged into W1. |
| A16 | Fixed. The message is cleared when the camera changes or the link becomes ready. In Geotag only, it is shown on the session screen. `AppModel.swift`, `SessionView.swift` |
| A17 | Fixed. The GPS chip shows accuracy only while tagging, and "Not tagging" for no fix or a refusing camera. The Accuracy readout is coloured by the accuracy limit. `SessionView.swift`, `GeotagView.swift` |
| A18 | Fixed. The reduced-range notice names this device, and the iPhone says "Control Center". `AppModel.swift` |
| A19 | Fixed. *Start geotagging* reports the failure it got back, not the last snapshot. `AppShortcuts.swift`, `AppModel.swift` |
| A20 | Fixed. The map follows fixes until the user pans or zooms. The marker has a label. `GeotagView.swift` |
| A21 | Fixed. `isSceneActive` starts from the application state on iPhone. `AppModel.swift` |
| A22 | Merged into W5. |
| A23 | Fixed. *Forget* shows only for the open camera, with its name in the button and in the dialog title. `SettingsView.swift` |
| A24 | Fixed. A found camera is placed by signal strength once, then keeps its row. `AppModel.swift`, `AddCameraView.swift` |
| A25 | Fixed, needs a device check. The bulb time field and the release-delay slider also save when the view goes away. `SettingsView.swift` |
| A26 | Fixed. The privacy manifest comments no longer mention sharing transcripts. 35F9.1 (system boot time) stays because shot timing uses `ContinuousClock`. All four `PrivacyInfo.xcprivacy` |

## Watch, config, docs and legal

| ID | Outcome |
|---|---|
| W1 | Fixed. The shutter tracks its touch with `@GestureState`. A cancelled touch, a disabled button or a vanished view releases focus without shooting. `ShutterButton.swift` |
| W2 | Fixed, needs a device check. Double Tap is off under the End-session dialog and the Timelapse sheet. watch `SessionView.swift` |
| W3 | Fixed. *End session* goes back to the list at once, before the teardown. `AppModel.swift` |
| W4 | Fixed, needs a device check. A notification delegate shows notifications while xGRC is frontmost but inactive (iPhone and watch). `xGRCWatchApp.swift`, `xGRCApp.swift` |
| W5 | Fixed, needs a device check. VoiceOver reads "Release delay" or "Bulb open" with the time left, and plain words otherwise (no glyphs). *Cancel countdown* is offered only during a countdown. A countdown or bulb start is announced. `ShutterButton.swift`, `ShutterAppearance.swift`, `AppModel.swift` |
| W6 | Fixed. *Sent* plays the `released` haptic on every device, apart from the focus click. `ShutterAppearance.swift`, `TallyHaptic.swift`, `AppModel.swift` |
| W7 | Fixed. The countdown digits are `Text(timerInterval:)`. The ring stays still when dimmed or with Reduce Motion. `ShutterButton.swift` |
| W8 | Fixed. The hint and the release-delay footnote change with *Tap to shoot*. watch `SessionView.swift`, `SettingsView.swift` |
| W9 | Fixed. The circular tile's button is labelled "Shoot", and the link state is its value. `ShutterTile.swift` |
| W10 | Fixed. No haptic or announcement per timelapse frame. Frame results are throttled like counter changes and raise no Live Activity alert. `AppModel.swift`, `ActivityPlanner.swift` |
| W11 | Fixed. The AF HOLD chip is a toggle to VoiceOver, with an On/Off value. `TallyControls.swift` |
| K1 | Merged into A26. |
| D1 | Fixed. The README drops the Demo camera step and the Action Button. `README.md` |
| D2 | Fixed. Product spec now covers: count caps, no Action Button, `ButtonStyle` plus label gesture, the tile's `openAppWhenRun`, the watch settings list, no transcript export or redaction, the manifest's one entry, and the About links. `10-14-26_product-spec-01.md` |
| D3 | Fixed. Architecture doc now covers: watch intents use `openAppWhenRun` (needs a device check), no Action Button, no Demo camera, no OSLog. `10-14-26_architecture-02.md` |
| D4 | Fixed. Phased plan now covers: no Action Button, no Demo camera, no transcript export; the short Sony write goes as a long write. `10-14-26_phased-plan-04.md` |
| D5 | Fixed: the README index lists the Sony/AlphaRemote, watch-gestures, Double Tap and this doc. The 10-17 doc is not renamed or edited, because another thread owns that work. `README.md` |
| D6 | Fixed. The code comments no longer claim the Action Button. `AppShortcuts.swift`, `ShutterTile.swift`, `CameraIntents.swift` |
| L1 | Fixed. The privacy policy says About links open xdqin.com or github.com under those sites' policies, next to Apple Maps. Last updated 19 October 2026. The contact and governing-law placeholders are left as they are. `privacy-policy.md` |

## New and changed tests

- `ShutterSafetyTests`:
  - Nikon reconnect shows `checkBulb`.
  - Sony reconnect close re-registers first.
  - A Sony bulb ended during the drop.
  - A late Sony bulb ack.
  - A stop drops a queued frame while an intent frame still runs.
- `SessionLifecycleTests`: forget while connecting; restored connects released; reconnect after a plain drop.
- `SessionCoordinatorTests`: intent bulb refused.
- `GeoTagStreamerTests`: relink after a failed reconnect.
- `ActivityPlannerTests`: stale dates; a throttled state replaced by the shown one; no alert per timelapse frame.
- `TranscriptTests`: the ring order.
- `BluetoothRobustnessTests`: Sony short write limit.

## Device test checklist

- Bluetooth off and on in Control Center during a session: the camera reconnects by itself (C1).
- Cold launch with Auto reconnect: the last session comes back; with Bluetooth off it shows a failed link with *Retry* (C2, C7).
- Sony BULB: drop the link during a bulb and come back; also switch the camera off and on in between. The shutter ends closed (C3).
- Nikon Time: same drop; the "check the camera" hint shows, and what the camera did is recorded (C3).
- Sony bulb whose shutter ack is slow (long NR, slow card): the bulb still closes (C4).
- Older Sony without DD30/DD31, *Location Info. Link* off: does geotagging tag photos, and does the advertisement bit show it (C11)?
- Sony with a short write limit (record it on watch and phone): the DD11 long write tags the photo (C17).
- Ricoh: start a movie on the body, then connect and disconnect xGRC: the movie keeps running (C24).
- iPhone: a 30 s release delay and a 2 min bulb with auto-lock at 30 s. The screen stays on and both finish (A1).
- *Start geotagging* from Siri with the phone locked and xGRC in the background: fixes arrive, or the intent opens the app (A12).
- VoiceOver on Settings: adjust the release-delay slider and the bulb time, go back, and check they were saved (A25).
- VoiceOver on the shutter during a countdown and a bulb: the time left is read (W5).
- Watch: Double Tap under the End-session dialog and the Timelapse sheet fires nothing (W2).
- Watch, wrist down during a release delay: the result notification shows (W4).
- Watch Smart Stack tile and the watchOS 26 Shoot control: Shoot opens xGRC and shoots there (`openAppWhenRun`, D3).
