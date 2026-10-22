# Phase 4 — iPhone and iPad app

Companion to [plan § Phase 4](10-14-26_phased-plan-04.md#phase-4--iphone-and-ipad-app) and the [product spec](10-14-26_product-spec-01.md), [architecture doc](10-14-26_architecture-02.md) and [protocol reference](10-14-26_ble-protocol-reference-03.md). This file records what Phase 4 built and the device tests it adds to the [Phase 6 device test pass](10-14-26_phased-plan-04.md#phase-6--device-test-pass).

**Status (2026-10-15):** code complete. The package has 85 tests, all passing on Linux with Swift 6.1; 6 of them cover the Live Activity planner added here. `project.yml` generates with XcodeGen 2.46: four targets, with the watch app embedded in the iPhone app and both widget extensions embedded in their apps. The iPhone app, its widgets and the shared app code need the Apple SDK and are first compiled at the start of Phase 6.

---

## What was built

| Piece | Where | What it does |
|---|---|---|
| iPhone and iPad app | `Apps/xGRC-iOS` | Cameras list (pull to refresh, Bluetooth banner, why the last session ended), Add camera (instructions, results by signal strength with brand and dBm, pairing sheet), Session (status strip, 140 pt shutter, AF hold, Delay chip, counters, Intervalometer), Geotagging (map with the fix and its accuracy circle, numbers, interval, Live Activity switch, Start/Stop), Settings and Onboarding. iPhone uses one navigation stack; iPad shows the cameras in a sidebar with the session beside them |
| Shared app code | `Apps/Shared/App` | `AppModel`, `ShutterButton`, the App Shortcuts and the setting wording now serve both apps. Watch-only pieces (Double Tap, the Smart Stack tile reload) and iPhone-only pieces (Live Activity, Controls reload) sit behind `#if os(...)` |
| Live Activity | `LiveActivityController` (app), `ActivityPlanner` and `ActivityState` (package), `SessionLiveActivity` (widget) | Requested from the foreground when a session starts (Settings › Live Activity, on by default). Lock Screen, Dynamic Island compact/minimal/expanded, and on iOS 18+ the small family the watch's Smart Stack shows, labelled "iPhone · camera" with no shutter. Status changes go out at once, counters and push times at most every 10 s; alerts only on a countdown release and on failures, never per timelapse frame; stale after 60 s without updates while geotagging; replaced before the 8-hour limit on the next foreground visit |
| Island shutter and Shoot control | `ShootLiveActivityIntent` (`Apps/Shared/LiveActivity`), `ShootControl` (iOS 18) | A `LiveActivityIntent`, so the press runs in the app process on the live link. The shutter shows only in a remote mode, connected, on a brand with background shooting. The control shoots when connected and opens xGRC (`xgrc://session`) when not |
| Shortcuts | `Apps/Shared/App/AppShortcuts.swift` | The same Shoot, Focus, Start and Stop geotagging intents as the watch, with result dialogs |
| Bond made by the maker's app | `SessionCoordinator.peripheralsConnectedElsewhere`, `CameraDriver.serviceUUIDs` | Add camera marks a camera another app already has connected to this iPhone and warns that the maker's app may hold its lock |
| Forget | `SettingsView` | The checklist: remove xGRC on the camera, and the camera in Settings › Bluetooth (which also unpairs the maker's app), with a button to Settings |
| AccessorySetupKit | `AccessorySetup.swift` | The Sony picker on iOS 18+, then the normal pairing flow; Forget removes its bond. Built but compiled out (decision 2) |
| Project | `project.yml`, `PrivacyInfo.xcprivacy` × 4 | iOS app and widget targets; the watch app is now `WKRunsIndependentlyOfCompanionApp` with the iPhone app as its companion; App Group on all four targets; privacy manifests declaring no tracking, no collected data, and the system-boot-time API for measuring elapsed time |

---

## Decisions and defaults

1. **Auto disconnect replaces the iPhone's 5-minute rule.** The spec ended a phone remote session 5 minutes after leaving Remote. The user asked for auto disconnect on 2026-10-15 (15 minutes idle or unreachable, user-selectable), and both apps now use that one rule.
2. **AccessorySetupKit is off until Phase 6.** It is unclear whether declaring it in Info.plist limits Core Bluetooth scanning to accessories set up through the picker, which would break brands that must pair on the app's own connection (Fujifilm). The code is behind the `XGRC_ACCESSORY_SETUP` compile flag. To try it, add that flag to the iOS target's Swift flags and these Info.plist keys: `NSAccessorySetupKitSupports` = `[Bluetooth]` and `NSAccessorySetupBluetoothCompanyIdentifiers` = `[012D]` (Sony). Then run device test 9.
3. **One Shoot control.** The spec describes a separate "Open xGRC" control on iOS 18–25. Instead, one control reads the App Group state and shows Shoot when a camera is connected or Open xGRC when not, so the user adds one control.
4. **`supportedModes` (iOS and watchOS 26) is not used yet.** The intents use `LiveActivityIntent` on iPhone and `ForegroundContinuableIntent` on the watch on every version; Phase 6 checks whether that is enough on 26.
5. **The iPhone settings use native controls** (a slider for the delay, pickers for the interval and auto disconnect). The Digital Crown rule applies to the watch only.
6. **Shared widget state moved to a new `SharedState` target.** It is Foundation-only, so both widget extensions link it instead of `Persistence`, which would have pulled in `BLEKit`.

---

## Device tests (run in Phase 6)

Record results in `docs/support/<brand>-<model>.md` (template in [Phase 1 doc](10-15-26_phase-1-watch-remote-01.md#support-record-template)) and every problem in the pass's issue list.

| # | Test | How | Record |
|---|---|---|---|
| 1 | Two clients | Pair the same camera from the phone after the watch | Both work, one at a time; ending the phone's session frees the camera for the watch |
| 2 | Phone remote | 100 shots from the phone | All acknowledged; no stuck buttons |
| 3 | Background geotag | 30 minutes with the phone locked, then the stationary run | Pushes continue; EXIF correct; the Live Activity stays current and is not marked stale |
| 4 | Island shutter | App in the background for 1 hour, tap the Island shutter | The shot fires without opening the app; the counter updates |
| 5 | Alerts | A 10 s release delay from the Island; a shot with the camera in playback | One alert on release; one "not confirmed" alert; none during a timelapse |
| 6 | 8 hours | Leave a geotag session running overnight, open the app | A fresh activity replaces the ended one |
| 7 | Control and Siri | Add the Shoot control and the Action Button; "Shoot with xGRC" | Each fires within 8 s; the control shows Open xGRC with no session |
| 8 | Watch Smart Stack | With the phone's activity running, raise the watch | "iPhone · camera" appears with no shutter |
| 9 | AccessorySetupKit | Build with decision 2's flag and keys; pair a Sony through the picker; then try scanning for a non-Sony camera | Pairing works; whether the plain scan still finds other brands decides if the picker ships |
| 10 | Maker's app | Connect the camera in Sony's app, then open Add camera | The warning shows on that camera |
| 11 | iPad | Run on an iPad in both orientations | Sidebar and session side by side; a Wi-Fi-only iPad warns about location accuracy (not built yet, see Known gaps) |

### Phase 6 bars for this part

- [ ] A 30-minute locked-phone geotag run with correct EXIF
- [ ] The Island shutter fires with the app in the background
- [ ] Control and Siri report the shot within 8 s

---

## Known gaps

- **Privacy policy and user agreement** were drafted on 2026-10-15 ([privacy-policy.md](../privacy-policy.md), [user-agreement.md](../user-agreement.md)) for hosting at https://xdqin.com/xGRC/privacy-policy and https://xdqin.com/xGRC/user-agreement. The contact email and governing law are still placeholders, and the text needs a review before the store listing (Phase 7). The licence was Apache 2.0; it is GPLv3 since 2026-10-21. The privacy manifests are in place.
- **Wi-Fi-only iPad warning** about location accuracy is not built yet.
- **Per-camera name editing and units** from the spec's iPhone Settings list are not built yet; the watch has neither either.
- **Connect on launch and Keep trying** settings from the spec are not separate switches yet: the last camera reconnects when its session is reopened, and auto disconnect bounds the trying.
