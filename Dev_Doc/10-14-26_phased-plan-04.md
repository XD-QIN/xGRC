# xGRC — Phased plan (solo developer, build first, test at the end)

Companion to the [product spec](10-14-26_product-spec-01.md), the [architecture doc](10-14-26_architecture-02.md) and the [protocol reference](10-14-26_ble-protocol-reference-03.md); the overview is in the [README](../README.md). This file holds the order of work, what each phase must produce, and how we know a phase is done.

**Assumptions this plan is written for**

- One developer. A Mac with Xcode, an Apple Developer account, one iPhone, one Apple Watch (Series 9 / Ultra 2 or newer for Double Tap; anything from Series 6 for the background link), and the camera or cameras already owned.
- No simulator hardware, no device lab, no BLE sniffer, no battery rig. The real camera is the test rig, and the app's own transcript log is the measuring instrument.
- **Build the whole app first, then test it on the devices in one pass.** Phases 1–5 write code and prove it against `FakeCamera` (a simulated body per brand) in package tests. Phase 6 installs the finished app on the watch and phone and runs every on-device test from one list, so issues are reported together and fixed in rounds.
- Questions that only the real device can answer (link lifetime, wake-up budget, pairing dialog on the watch, ack behaviour) get a documented default when the feature is built. Phase 6 measures them, and the defaults change only if a measurement says so.
- The first driver is Sony, because the camera brand on hand was not known when Phase 1 started. Phase 5 adds every other brand the protocol reference specifies, so whichever camera you own is covered by the time testing starts.

## Phase overview

| Phase | Name | What exists at the end |
|---|---|---|
| 1 | Watch remote | The watch app pairs with a Sony camera and takes acknowledged photos (code complete) |
| 2 | Watch geotag | The watch streams GPS to the camera for EXIF with the phone at home |
| 3 | Watch polish | Release delay, intervalometer, Double Tap, Smart Stack tile, every error state, onboarding, accessibility |
| 4 | iPhone and iPad app | Same package on the phone, Live Activity, Controls and Shortcuts |
| 5 | Other brands | Fujifilm, Ricoh, Canon and Nikon drivers, each with a simulated body and tests |
| 6 | Device test pass | Everything above installed and tested on the real watch, phone and camera, issues fixed in rounds |
| 7 | Beta and 1.0 | TestFlight, store submission with a demo video for reviewers |
| after | Research | Nikon SnapBridge mode, GPX export, extra brands |

**Done when, for each build phase (1–5):** the work items are written; package tests for everything that needs no hardware pass; the phase's file (`phase_N.md`) lists what was built and adds its device tests to the Phase 6 list. No phase waits for a device test.

---

## Phase 1 — Watch remote

Goal: the smallest app that pairs the watch with a camera and takes a photo you can trust.

**Progress:** code complete (Sony driver first); see [Phase 1 doc](10-15-26_phase-1-watch-remote-01.md).

### Set up

- XcodeGen `project.yml`, the Swift package `Packages/xGRCCore` (`BLEKit`, `CameraKit`, `SessionKit`, `Persistence`, `DesignKit`; `LocationKit` arrives in Phase 2) and two targets for now: the watch app (`bluetooth-central` and `location` in `UIBackgroundModes`, Bluetooth and location usage strings) and a watch widget extension shell. The iOS app target is created in Phase 4.
- Swift 6 strict concurrency from the first file; `BLEKit` confined to one serial queue shared with `CBCentralManager`, created in the watch app delegate's launch method with a fixed restore identifier.
- Package tests for what needs no hardware: Sony protocol encoding and decoding, the `ShotSequencer` gesture table on an injected clock, and the session against `FakeCamera`.

### Build

1. `BLEKit`: foreground scan with app-side classification, connect, service discovery, read, write (with and without response), subscribe, link events, typed ATT errors, the transcript logger (schema v1, JSON Lines).
2. `SonyDriver` exactly as the protocol reference specifies: `pair`, `reconnect`, `press`/`release`, `shotScript`, `events`, with the `FF02` acknowledgement.
3. `ShotSequencer` with the gesture table (single tap = focus, double tap = shoot, timed bulb on one tap when a bulb time is set, grace period, AF hold) and `ShotResult`.
4. `SessionCoordinator` with the single-camera rule and the reconnect policy's static-address path (pending connect with auto-reconnect; `driver.reconnect()` on every reconnect).
5. Watch UI: Cameras list, Add camera with the Sony pairing instructions, Pairing screen, the Shutter page with the five-state button, the confirmed/sent counter, a Settings page with Forget camera and Export transcript, and a Demo camera backed by `FakeCamera`.
6. Keychain `ClientIdentity` and `CameraIdentity`; Codable `CameraRecord` store.

Carried into Phase 3: the foreground rescan on disconnect (the architecture doc asks for it on the watch alongside the pending connect). Done in Phase 3.

---

## Phase 2 — Watch geotag (phone at home)

Goal: photos taken on a walk with only the watch carry GPS EXIF.

**Progress:** code complete; see [Phase 2 doc](10-15-26_phase-2-watch-geotag-02.md).

### Build

1. `LocationKit` / `LocationSource`: `startUpdatingLocation()` with `allowsBackgroundLocationUpdates`, best accuracy, `.otherNavigation`, `pausesLocationUpdatesAutomatically = false`, inside a `CLBackgroundActivitySession`; the validity, accuracy and movement rules from README's geotag defaults; re-create the session at launch when a session record is open. A `FakeLocationSource` drives the tests and the Demo camera.
2. Sony location-link calls: `startLocationLink` / `stopLocationLink`, `updateLocation` with the `DD21`-driven 91/95-byte packet (real offset and DST), `syncClock`, `keepAlive` policy (`CC02`, off by default).
3. `GeoTagStreamer` with the push interval and no-fix behaviour, tested on an injected clock.
4. `WatchRuntimeController`: owns the background location session and reacts to the `CBError` budget codes in the characteristic-update callback.
5. Watch Geotag page: fix quality, last push, pushes, Stop; the Remote-or-Geotag choice for pre-α7 IV Sony bodies; the "Turn on … on the camera" warnings.
6. Package tests against the golden vectors in the protocol reference's sources (the 95-byte Sony packet) and a geotag session over `FakeCamera`.

Default until Phase 6 measures it: notifications under the location session are assumed to count against the Bluetooth wake-up budget, so the watch keeps its own notification rate low.

---

## Phase 3 — Watch polish

Goal: the watch app is complete and pleasant to use.

**Progress:** code complete; see [Phase 3 doc](10-15-26_phase-3-watch-polish-03.md). Includes the mode setting (Remote + Geotag, Remote only, Geotag only) the user asked for.

### Build

- Release delay (1–60 s, Digital Crown) with the countdown ring, auto-focus, fire, one haptic while active, and the wrist-down fallback (result on next raise, local notification).
- Intervalometer sheet with the [intervalometer rules](10-14-26_architecture-02.md#intervalometer-rules) (start-to-start, missed vs failed, AF each frame, shutter-ready gating on brands with acks).
- Double Tap: `handGestureShortcut(.primaryAction, isEnabled: selectedPage == .shutter)` behind the watchOS 11 availability check; it fires Shoot, cancels a countdown and ends bulb, and does nothing on the Geotag page.
- Smart Stack tile: link state, push age, Shoot via an intent with `openAppWhenRun` (opens xGRC and shoots there), Double Tap declared only while a session runs.
- watchOS 26+ Shoot control for Control Center and the Smart Stack (no Action Button: only workout apps get it).
- Every States & errors row that applies to the watch, built against `FakeCamera` fault injection (camera off, out of range, busy with the maker's app, feature off, card out).
- Foreground rescan on disconnect and the reduced-range banner.
- Onboarding: mode choice, Return to Clock steps, don't force-quit, brand-specific tips.
- Auto disconnect after 15 minutes idle or without the camera (user-selectable, Never or 5–60 minutes).
- Mode setting: Remote + Geotag, Remote only or Geotag only, in Settings and at first launch, remembered on the watch; the session shows only the pages the mode uses.
- Accessibility actions on the shutter button (Focus, Shoot, Start/Stop bulb, Cancel countdown) and state announcements.
- Package tests for every gesture-table row and intervalometer rule.

---

## Phase 4 — iPhone and iPad app

Goal: the same package on the phone, with the Dynamic Island.

**Progress:** code complete; see [Phase 4 doc](10-15-26_phase-4-iphone-ipad-app-04.md). AccessorySetupKit is built but off until Phase 6. The licence is GPLv3 (`LICENSE`; Apache 2.0 until 2026-10-21), and the privacy policy and user agreement are drafted at the root for hosting at https://xdqin.com/xGRC/privacy-policy and https://xdqin.com/xGRC/user-agreement (all decided 2026-10-15; open items in [Phase 4 doc § Known gaps](10-15-26_phase-4-iphone-ipad-app-04.md#known-gaps)).

### Build

- iOS app target and iOS widget extension; the shared screens laid out for phone and iPad; `UIApplicationDelegateAdaptor` creating the central at launch with the restore identifier; state restoration. The watch target switches from watch-only to `WKRunsIndependentlyOfCompanionApp` with the iOS app as its companion.
- Background geotag on iPhone (location session, no auto-pause) and the background-shooting rule per brand (Island shutter only where remote and geotag can share a session).
- Live Activity (compact, minimal, expanded ≤ 160 pt, Lock Screen), `ShootLiveActivityIntent`, alerts only on countdown release and failures, stale date, re-request after 8 h, supplemental small family for the watch Smart Stack labelled "iPhone".
- Controls (iOS 18) using the same intent, "Open xGRC" control when no session on iOS 18–25, `supportedModes` on iOS 26; App Intents Shoot / Focus / Start / Stop with result dialogs.
- AccessorySetupKit pairing on iOS 18+ for brands that tolerate it (Sony); Core Bluetooth pairing otherwise and on iOS 17.
- Add-camera detection of a bond made by the maker's app; the Forget checklist with its side-effect copy.
- Privacy manifests in all four executables; privacy policy URL (done: https://xdqin.com/xGRC/privacy-policy); licence (done: GPLv3, changed from Apache 2.0 on 2026-10-21).

---

## Phase 5 — Other brands

Goal: every brand the protocol reference specifies has a driver, built from the protocol reference and proven against a simulated body, so the device test pass covers whichever camera you own.

**Progress:** code complete: Fujifilm (secure and legacy), Canon Remote and Smartphone, Nikon Remote and Ricoh GR, each with a simulated body and tests (120 package tests pass). Where this differs from the items below (Ricoh acks logged rather than claimed, no Fujifilm time packet, one Canon shoot-mode constant instead of a setting, tooling moved to Phase 6) is explained in [Phase 5 doc](10-15-26_phase-5-other-brands-05.md#decisions-and-defaults).

**After Phase 5:** bulb is timed. A *Bulb* setting (Off, or 1 s to 99 min 59 s since 2026-10-16; typed on the phone, two Digital Crown wheels on the watch) replaces the long-press bulb: with a bulb time set, one tap opens the shutter, the button counts down and the shutter closes at zero, and a tap closes it early. Holding the button no longer opens bulb. Its device test is [Phase 1 doc](10-15-26_phase-1-watch-remote-01.md#device-tests-run-in-phase-6) test 5.

### Per brand, in order of value

Each driver gets a simulated body (the `FakeCamera` pattern) and package tests against the protocol reference's golden vectors.

1. **Fujifilm** (secure and legacy): registration on the app's own connection, NOT1 time requests, pull-model geotag with send-time stamps and the monotonic rule, the 15 s watchdog, identity-address change → Pair again. Shots reported as *assumed* until an ack source is found.
2. **Ricoh GR III/IIIx and GR IV**: passkey pairing, single-write capture with AF and capture acks, GEO Tag confirm, GPS packet, clock; never write `9111CDD0`.
3. **Canon Remote and Smartphone**: drive-mode hint, write-without-response readiness; Smartphone mode with platform byte `0x01` first, both `00030010` values behind a setting, `00030031` decoded as the candidate ack; the one-function-at-a-time rule in the mode picker.
4. **Nikon Remote**: four-stage handshake, Bulb-as-Time scripts, `00002084` indications logged and decoded where the protocol reference allows.

### Tooling (moved to Phase 6, when there are real captures)

- `Tools/Transcript/`: PacketLogger/btsnoop → transcript converter and the packet-aware redactor, so official-app captures and tester exports become replayable fixtures.
- `BLEKit` tests over CoreBluetoothMock, run locally.

The ack research cells in the [architecture doc](10-14-26_architecture-02.md#acknowledgement-per-brand) (Fujifilm, Canon Smartphone, Nikon) need a capture of the official app on a real body, so they close in Phase 6 or 7, not here.

---

## Phase 6 — Device test pass

Goal: the finished app works on the real watch, phone and camera, and every [open platform question](10-14-26_architecture-02.md#open-questions--risks) has a measured answer.

### How the pass runs

1. **First build on the Mac.** `xcodegen generate`, set the team and bundle prefix in `Config/Local.xcconfig`, build and install the watch and phone apps. The Apple-only code (UI, Core Bluetooth, Keychain, Location, widgets) is first compiled here, so expect compile errors; paste them in one message and they are fixed together before the test list starts.
2. **One pass through the test list below**, in order, recording results in `docs/support/<brand>-<model>.md` (template in [Phase 1 doc](10-15-26_phase-1-watch-remote-01.md#support-record-template)) and every problem in one issue list (GitHub issues, or one message with a numbered list). The app has no transcript export any more, so note what the screen said and when.
3. **Fix round.** All reported issues are fixed together on one branch, then the affected tests are re-run. Repeat until the done-when bars below hold.

### Test list

Each phase's file holds the detailed steps; this is the order to run them.

**Watch remote** (detail in [Phase 1 doc](10-15-26_phase-1-watch-remote-01.md#device-tests-run-in-phase-6))

- Pair from the watch with the iPhone app not installed and the phone's Bluetooth off; note the pairing dialog (Just Works / numeric comparison / passkey) and whether the camera accepted it. "Not supported on watch" is an allowed outcome for a brand.
- 100 shots, each *acknowledged* (or *assumed* on a brand without acks), zero stuck button states; check the write order in the transcript.
- Leave the app for 2, 5 and 10 minutes: does the link survive? Note budget errors.
- *Return to Clock* set to 1 hour: the Shutter page stays up with the wrist down and the haptic plays while the screen is awake.
- Walk out of range and back: reconnect time, reduced-range banner.
- Feature-off and busy errors (Sony *Bluetooth Rmt Ctrl* off → ATT `0x90`; `EE01` needed at first pairing or not).

**Watch geotag** (detail in [Phase 2 doc](10-15-26_phase-2-watch-geotag-02.md#device-tests-run-in-phase-6))

- 20 photos over 30 minutes on a walk with the wrist down: EXIF on the camera or the Mac (local time correct, position plausible).
- 30 minutes stationary on a tripod with the wrist down: pushes continue and the link holds.
- 2-hour walk with the phone at home: reconnect count and watch battery before and after (targets in the [Budgets](10-14-26_architecture-02.md#budgets): ≤ 1 reconnect per 30 minutes, ≤ 15 %/h).
- Transcript check: did geotag notifications spend the Bluetooth wake-up budget while the location session ran? If yes on a pull-model brand, raise the camera's sync interval or mark watch geotag foreground-only.
- Force-quit mid-session and relaunch; crash a debug build and confirm Core Location relaunches it.
- Alongside an Apple Workout session: pushes continue; note which app wins the wrist raise.
- Sony: a 10-minute segment with *Keep camera awake* on and off; count shots lost after the camera wakes.

**Watch polish** (detail in [Phase 3 doc](10-15-26_phase-3-watch-polish-03.md#device-tests-run-in-phase-6))

- Each mode on the real camera: Remote only never asks for location; Geotag only tags photos with *Bluetooth Rmt Ctrl* off; switching mode mid-session changes the pages and the camera link at once; the choice survives a relaunch.
- A 200-frame timelapse on a tripod: 200 acknowledged (or sent) frames, no run aborted by a transient disconnect.
- Release delay fires with one haptic while active and shows its result after a wrist-down countdown.
- Double Tap, the Smart Stack tile and the watch Shoot control each take a photo.
- Each watch error state provoked on the real camera where possible (camera off, out of range, busy with the maker's app, feature off, card out).
- VoiceOver and AssistiveTouch pass.

**iPhone and iPad**

- Pair the same camera from the phone (two clients). The watch can still take the camera while the phone app runs; the phone's session releases the Sony lock on end.
- 100 shots from the phone; 30-minute background geotag with the phone locked and EXIF checked, including the stationary run. Fujifilm: first iOS EXIF confirmation.
- Island shutter with the app backgrounded for 1 hour on a brand that allows background shooting; Control and Shortcut each fire within 8 s and report the result.
- Detail and the rest of the iPhone list in [Phase 4 doc](10-15-26_phase-4-iphone-ipad-app-04.md#device-tests-run-in-phase-6).

**Other brands** (whatever bodies are on hand, borrowed or rented; the rest go to TestFlight testers in Phase 7)

- The watch-remote and geotag bars above on at least one body per brand.
- Ack research: capture the official app during shooting with the iPhone Bluetooth logging profile and PacketLogger, decode the candidate notifications, and close the brand's cell in the architecture doc's ack table.

**Checks from the code review** (October 2026; the fixes are in place and tested on simulated bodies, these need hardware)

- First build: the generated project embeds the watch app in the iPhone app and each widget extension in its app; the Live Activity types (`SessionActivityAttributes`, `ActivityState`) compile as `Sendable` under strict concurrency. The iPhone widget builds with `WIDGET_EXTENSION`, which leaves out `ForegroundContinuableIntent`; if the watch widget also refuses it, set the same flag there (its tile then says "Open xGRC" instead of shooting) and record it. Result (first build, Xcode 27): the watch widget refuses it too, so it now builds with `WIDGET_EXTENSION`; test 10 decides whether the tile's Shoot needs `supportedModes`. The iPhone Shoot control is one `ShootControlIntent` and needs iOS 18.2, because a control template cannot branch between two intent types.
- Canon Remote bulb: in B, is one `0x8C` press-to-start and the next press-to-stop, or must the press be held? Record which and check the timed bulb closes the shutter.
- Canon Smartphone bulb: does `00 01` held until `00 02` keep a bulb open for the set time? After a link drop with the bulb open, the reconnect's `00 02` closes it.
- Timed bulb with the camera not in B or Time: Nikon and Sony take two separate shots (press opens, press closes); Fujifilm in continuous drive may burst for the whole bulb time. Record what each does and whether the hint to set BULB is enough.
- Nikon Time across a link drop: the second press on reconnect closes the exposure, and nothing fires twice.

**Checks from the AlphaRemote comparison** (October 2026, [comparison doc](10-15-26_sony-alpharemote-review-06.md); tested on the fake camera, these need a Sony body)

- Sony timed bulb in BULB: one tap opens the shutter, the shutter stays open after the press is released, and the timed second press closes it; the EXIF exposure time matches the bulb time within a second. A tap during the bulb closes it early. Note in the transcript which `FF02` values arrive at open and close (`02 A0 20`, then `02 A0 00`?).
- Sony bulb with AF that cannot focus (lens cap on, AF-S): the shutter ack never comes, the bulb is reported not confirmed, and no second press goes out (nothing opens).
- Sony bulb across a link drop: walk out of range with the bulb open; on reconnect the second press closes it and the release follows; nothing opens a second time.
- Sony timelapse with shutter-open time above 1 s: each frame opens and closes; Stop closes an open frame at once.
- `FF02` values: record any byte-2 value other than `00` and `20` and any value longer than 3 bytes.
- Newer Sony bodies: the transcript shows a services-modified event shortly after connecting, the session re-registers, and the first shot after it is acknowledged.
- Nikon handshake: the four stages are accepted on every reconnect, not only at pairing; note any body that expects a different first message.
- Re-subscribe on reconnect: every brand's subscriptions come back after the camera sleeps and wakes; record time from link up to Ready, and any reconnect that hangs on a subscribe.
- Missing altitude: a fix without altitude is sent as 0 m (Canon, Fujifilm, Ricoh). Check the EXIF altitude of such a photo and decide whether to leave it out instead.
- Sony maximum write length: the transcript logs it; record it on the watch and the phone. Below 95 bytes the `DD11` packet goes as a long write (since 2026-10-19); check the camera accepts it and tags the photo.
- Ricoh: the stop the app sends on disconnect is harmless when nothing is running.
- Watch: the Crown turns a setting as soon as its picker opens, without a tap first.
- Scan: with no camera advertising, Add camera stops scanning after 30 s.
- Notification permission is asked on screen (onboarding or the first camera), and a wrist-down result then arrives as a notification.
- iPhone 26 and watchOS 26: the Shoot control and the intents still open xGRC when no camera is connected (they use `OpenURLIntent` and `ForegroundContinuableIntent`, not the newer `supportedModes`).

**Checks from the gestures and settings round** (October 2026, [round doc](10-16-26_watch-gestures-and-settings-01.md); package-tested on simulated bodies, these need the devices)

- Watch hand Double Tap (Ultra 2, watchOS 11+) on the Shutter page with *Tap to shoot* off and on: each pinch focuses and shoots one photo; the shot haptic plays; nothing fires from the Geotag or Settings page.
- Watch *Tap to shoot* on: one screen tap focuses and shoots one photo (no second tap needed), *tap = shoot* shows under the button, AF hold and Focus hold are hidden. With a camera without acks, the *released* haptic is distinct from the focus click. Off: tap focuses, double tap shoots, as before.
- Watch: scrolling the Shutter page by dragging from the button with *Tap to shoot* on does not fire a shot. If it does, record it.
- Bulb time: typed minutes and seconds on the phone (90 s becomes 1 min 30 s; 200 min stops at 99 min 59 s; 0 and 0 is Off); on the watch the two wheels turn with the Crown and a tap moves the Crown to the other wheel. A 61-minute bulb on Fujifilm shows the 60-minute note and the camera closes the bulb itself.
- Auto reconnect on: turn the camera off and on mid-session, the session comes back; force-quit the app mid-session and relaunch, the same camera's session reopens (with geotagging if it was on). Off: turning the camera off ends the session with "Auto reconnect is off"; relaunch shows the camera list.
- Live Activity: *End session* removes it at once, also with the camera already off or out of range; force-quit or a debug stop with a session running leaves no Live Activity behind after the next launch.
- Appearance: System, Light and Dark switch the iPhone app at once, including sheets, and System follows the phone again.
- About: the version matches the build, and each of the four links opens (on the watch, in its web view).

### Done when

- 100 acknowledged (or assumed) shots on the watch and on the phone, zero stuck states.
- The watch link survives leaving the app for 10 minutes, or the reason it does not is written down.
- 20 photos with correct GPS EXIF from a watch-only walk; the stationary run and the 2-hour walk are recorded with reconnect count and battery figures.
- The wake-up budget question is answered and written into the product spec's watch runtime row.
- Release delay, intervalometer, Double Tap, the tile and the watch Shoot control meet their bars; VoiceOver and AssistiveTouch passes recorded.
- Phone and watch both drive the same camera, never at the same time, with correct hand-over; Island, Control and Shortcut criteria met.
- Pairing dialog type, reconnect time and negotiated connection interval are in the support record for every brand tested.
- No issue from the pass is left open without a decision.

---

## Phase 7 — Beta and 1.0

### Build and prepare

- TestFlight to external testers (watch and phone), with a demo video in the review notes, as App Review has no camera (the Demo camera was removed 2026-10-16). Testers who own brands not tested in Phase 6 run the app and report what the screen said, with a sample photo (the transcript cannot be exported).
- Support site or page: pairing guide per brand and generation (localised camera menu strings from the makers' manuals), FAQ (Busy, Rmt Ctrl, Return to Clock, reduced range, Forget side effects), privacy policy, contact.
- Store assets: screenshots for iPhone, iPad and watch, a short preview video, "compatible with" wording for brand names, review notes with the background-mode justification and a demo video of a real pairing and shot.
- Crash triage through Xcode Organizer and MetricKit; a firmware-watch habit (each maker's firmware page) with a smoke test after each release.

### Done when

- ≥ 20 external testers across at least two brands; crash-free sessions ≥ 99.5 %; no severe issue open for more than a week; support records exist for every brand shipped.
- Approved on the App Store; first-week crash rate holds the beta bar.

---

## After 1.0

- Nikon SnapBridge mode: capture SnapBridge on an iPhone during pairing; if it uses the External Accessory picker, mark the mode permanently out of scope in the product spec; otherwise compare with nsg's Android trace and decide.
- GPX export, Sony AF-ON focus option, optional watch-name sync, macOS Catalyst, further brands (GoPro has an open BLE spec).
- If a hardware simulator ever becomes worth it (for regression tests without a camera), a Mac peripheral covers Canon and Ricoh and an ESP32 would be needed for the others.

---

## What stays small on purpose

- No device lab: the camera you own is the rig; other brands come from borrowing, renting and testers.
- No sniffer: the pairing dialog the watch shows, and whether the camera accepts it, is the answer; a PacketLogger capture on the Mac is the only optional extra and needs no hardware.
- No battery rig: battery percentage before and after a timed walk.
- No CI: package tests run locally, and device testing stays manual, in one pass.
