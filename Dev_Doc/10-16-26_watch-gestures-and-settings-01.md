# Watch gestures and settings round

Date: 2026-10-16. Nine items the maintainer listed after the first device install. Every change below is package-tested where it has no Apple-only code; the UI, Live Activity and watch code compile only in Xcode on the Mac.

## What changed

| # | Ask | What was built |
|---|---|---|
| 1 | Index finger tap on the watch: single to focus, double to shoot | Hand **Double Tap** (thumb and index finger pinched twice) shoots on the Shutter page, focusing first when nothing is held. **A single pinch cannot be done:** watchOS gives apps only the double pinch, as `handGestureShortcut(.primaryAction)` on one control (Series 9, Ultra 2 and later, watchOS 11+). There is no API for a single pinch, so "pinch once to focus" is left out. |
| 2 | Watch Settings toggle: Double Tap focuses then shoots with a haptic, and a single screen tap focuses then shoots; off by default | **Tap to shoot** under Shutter, off by default. On: a screen tap sends the half-press on touch-down and shoots on lift, after that half-press's focus ack (or the brand's settle time). There is no double-tap window, and AF hold and Focus hold are hidden. A hand Double Tap focuses and shoots as in item 1. A confirmed shot plays the *fired* haptic. On brands without a shutter ack, a new *released* haptic plays (`WKHapticType.start`), so the shot feels different from the focus click. A touch that moves more than 12 pt before lifting is treated as a scroll: it releases focus and does not shoot. Bulb mode (bulb time set) still opens the bulb on one tap. |
| 3 | No Demo camera toggle | Removed from the watch (both Settings screens) and the phone. `AppSettings.showDemoCamera` and `FakeCamera` stay for the package tests. Phase 7 still has to decide how App Review sees the app without a camera. |
| 4 | Auto reconnect toggle, on by default, that reconnects and resumes the previous session | **Auto reconnect** under Connection on both devices. On: a dropped link reconnects as before, and at launch the session that was running when the app stopped reopens, with geotagging if it was on. Before this change, only an open geotag session was restored. Off: a dropped link ends the session and the camera list says why. If a bulb may still be open, the app still reconnects so it can close it. At launch with it off, the old session is dropped. |
| 5 | Bulb time typed in, with a researched upper limit; Crown wheel on the watch | Phone: minutes and seconds fields with the number pad, saved when the keyboard closes (seconds past 59 carry over, so 90 s becomes 1 min 30 s). Watch: two wheels, minutes and seconds. The Crown turns the selected wheel, and tapping the other wheel moves the Crown to it. The limit is **99 min 59 s** (see below). |
| 6 | No diagnostics | *Export transcript* removed from the watch and the phone, with `AppModel.prepareTranscript` and `SessionCoordinator.exportTranscript`. The transcript logger stays in memory for development. The privacy policy, README and spec now say it cannot be exported. |
| 7 | Dark and light switch | **Appearance** (System, Light, Dark) on iPhone and iPad. It is set on the window (`overrideUserInterfaceStyle`) so the UIKit-resolved Tally colours follow it and System really goes back to the system. The watch stays dark: watchOS has no light appearance and the Tally tokens are dark there. |
| 8 | Live Activity ends as soon as the session ends | Three causes fixed. (a) `SessionCoordinator.endSession` published the ended state only after the teardown, which waits on writes to a camera that may be gone; it now publishes first. (b) *End session* ends the activity before the camera is released, and a late snapshot cannot bring it back. (c) A run that stopped without ending it (force quit, crash, Xcode stop) left the activity on the Lock Screen; launch now ends leftovers, and `applicationWillTerminate` ends all of them. |
| 9 | About in Settings: version, privacy policy, user agreement, developer site, GitHub | **About** at the bottom of Settings on both devices: version (`0.1.0 (1)`), Privacy Policy, User Agreement, Developer (https://xdqin.com) and GitHub (https://github.com/XD-QIN/xGRC). On the watch the links open in the watch's web view. |

## Bulb upper limit

The cap is the longest bulb a supported brand documents for its own Bluetooth remote:

| Brand | Longest bulb | Source |
|---|---|---|
| Canon | 99:59 (min:s) for *Remote Bulb Shooting* in Camera Connect; the in-camera bulb timer goes to 99:59:59 | Canon Camera Connect manual, Remote Bulb Shooting (https://cam.start.canon/en/S003/manual/html/UG-03_RemoteCamera_0110.html) |
| Fujifilm | 60 min (camera closes the bulb itself) | X-T5 specifications, "Bulb: up to 60min." (https://www.fujifilm-x.com/en-us/products/cameras/x-t5/specifications/) |
| Sony | No stated limit with the Bluetooth remote (toggle) | Sony help guides, see the protocol reference |
| Nikon | No stated limit for Time | Nikon Z manuals; only *extended shutter speeds* stop at 900 s |
| Ricoh GR | No bulb over Bluetooth in this driver | — |

So `AppSettings.maxBulbSeconds` = 99 × 60 + 59 = 5999 s, and `SequencerConfiguration.bulbLimit` uses it (it was 30 min). Above 60 minutes on a Fujifilm body, the Shutter page notes that the camera ends the bulb by itself. The release after that is harmless because Fujifilm's bulb is a held press.

## Code map

- `Persistence/Records.swift`: `AppSettings.tapToShoot` (false), `autoReconnect` (true), `appearance` (`AppearanceSetting.system`), `maxBulbSeconds`. Older files decode with these defaults.
- `SessionKit/ShotSequencer.swift`: `SequencerConfiguration.tapShoots`, the `touchMoved` input, `beginShot(awaitingFocusSince:)` (waits for the tap's own focus ack from its event mark, so an ack that came before the lift counts), `mayHaveShutterOpen`.
- `SessionKit/SessionCoordinator.swift`: `restoreSession()` resumes any last session, `endAfterLinkLoss`, `SessionEndReason.linkLost`, and the ended state published before teardown.
- Apps: `AboutInfo.swift` (new, shared), watch `ShutterSettings`, `BulbTimeView`, `ConnectionSettings`, `AboutSection`; phone `BulbTimeField`, Appearance and About sections; `LiveActivityController.endNow / endStale / endAllBeforeExit`; `TallyHaptic.released`.

## Tests added

`ShotSequencerTests`: tap to shoot (one tap, two taps, hand Double Tap, scroll does not shoot, scroll without the setting is a single tap). `SessionLifecycleTests`: auto reconnect off ends on a link drop, on reconnects, launch restore on and off. `PersistenceTests`: old settings files take the new defaults.

The Swift toolchain could not be installed in this cloud session (download.swift.org is blocked), so `swift test` was not run here. Run `cd Packages/xGRCCore && swift test` on the Mac and build the app targets in Xcode before merging.

## Device tests

Added to the [plan's Phase 6 list](10-14-26_phased-plan-04.md#test-list) under "Checks from the gestures and settings round".
