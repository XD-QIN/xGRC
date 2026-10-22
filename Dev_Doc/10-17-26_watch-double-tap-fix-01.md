# Watch Double Tap fix and End session button

Date: 2026-10-17.

## Problem

On the first device test of the gestures and settings round (Apple Watch Ultra 2), the hand Double Tap did not focus or shoot on the Shutter page. The watch did its system Double Tap action (scroll and page) instead.

## Cause

`ShutterButton` was a `Button` with a custom `PrimitiveButtonStyle`. That style's body was a bare view with a `DragGesture`, so the button was no longer a system control. `handGestureShortcut(.primaryAction)` needs a buttonlike control on screen (Apple, *Enabling the double-tap gesture on Apple Watch*, https://developer.apple.com/documentation/watchos-apps/enabling-double-tap). With no control found, watchOS fell back to its own priorities: scroll view, then vertical tab paging.

## Fix

`Apps/Shared/App/ShutterButton.swift`:

- The shutter is a real `Button` with a plain `ButtonStyle` (`ShutterButtonStyle`) that keeps the system's control handling. Its action sends *Shoot*, so Double Tap, VoiceOver and the Smart Stack shoot as before.
- Screen touches are read by a `DragGesture` on the label, which reports touch-down, touch-up and touch-moved to `ShotSequencer` as before. The action ignores a call that comes while a finger is down or within 0.5 s of the lift, so a screen tap never also fires *Shoot* through the button.
- The style clips the label to a circle, so the Double Tap highlight is the disc.

Nothing changed in the sequencer, so the gesture rules from the last round are the same. Double Tap only works while the camera is connected and the Shutter page is showing.

## Device checks

- Shutter page, camera connected: Double Tap focuses and shoots, and the disc highlights.
- One screen tap focuses (or, with *Tap to shoot* on, focuses and shoots). Two quick taps shoot. No extra shot after any tap.
- Scrolling down from the shutter still scrolls and does not shoot.
- VoiceOver: activating the shutter shoots; the Focus action focuses.

## End session on every watch page

The maintainer asked for an End session button on the watch. It was only at the bottom of the Settings page. A red stop button now sits in the top-right corner of every session page (Shutter, Geotag, Settings) and asks "End this session?" before it ends, like the phone. The Settings page button stays.

Device check: tap the stop button on the Shutter page, confirm, and the watch goes back to the camera list with the camera released.

## Shooting with the watch screen dark

The maintainer found that nothing works while the watch screen is black. This is a watchOS limit, not a bug in xGRC:

- With Always On, wrist down dims the screen. With Always On off, the screen turns off. Either way watchOS uses the first touch to wake the screen and does not pass it to the app, and Double Tap does nothing until the screen has brightened (a wrist raise or a touch). No app can change this, and the API that kept an app awake (`isFrontmostTimeoutExtended`) was removed in watchOS 7. Extended runtime sessions are limited to health categories, and workout sessions are excluded (decision 6).
- The Ultra's **Action Button** works with the screen dark, but xGRC cannot shoot from it yet. Apple says watchOS 26 controls can be used with the Action Button (WWDC25 *What's new in watchOS 26*, https://developer.apple.com/videos/play/wwdc2025/334/), and the watch widget extension ships `ShootControl`. On the first device test (Ultra 2, watchOS 27.0.1, build 52261d0) xGRC did not appear in the watch's Action Button settings. Even when the control does show up, its `ShootIntent` runs in the widget extension's process, where `IntentBridge.handler` is `nil` and there is no Bluetooth link, so it can only say "Open xGRC". Making it shoot needs the intent to run in the app's process. That is a separate change, and it has to be tried on the device.

Change: while the screen is dimmed, the Shutter page hint reads "Raise your wrist to shoot" (`isLuminanceReduced`), so the dimmed screen says why taps do nothing.

Device checks:
- Wrist down with Always On: the Shutter page shows "Raise your wrist to shoot". Raise the wrist, then Double Tap shoots.
- Check where watchOS lists xGRC's Shoot: Control Center (Edit, Add), the Smart Stack, Settings › Action Button, and the Shortcuts app on the watch. This shows which path a dark-screen shot could use.

## Shoot control and tile run in the app

On the device, xGRC's Shoot control showed in the watch's Control Center but did nothing. Its intent ran in the widget extension, which has no camera link. On watchOS, `ShootIntent` and `FocusIntent` now set `openAppWhenRun`, so the system opens xGRC and performs them in the app's process. WidgetKit documents this for intents with `openAppWhenRun` (*Adding interactivity to widgets and Live Activities*). The property is deprecated on watchOS 26 in favour of `supportedModes`, but Apple doesn't say which process `supportedModes` uses, so the documented one stays until a device test says otherwise. The Smart Stack tile's Shoot goes through the same intent.

If the app was not running, it opens first and the camera may still be connecting. In that case Shoot answers "Open xGRC to connect the camera.", and the next press shoots.

Live Activities: the watch app cannot start its own. ActivityKit and `LiveActivityIntent` are iOS-only. A session started on the iPhone shows its Live Activity in the watch's Smart Stack (watchOS 11+), and its Shoot runs on the iPhone. With Always On, xGRC's own dimmed screen stays visible with the wrist down and shows the link and shot count.

Device checks:
- Control Center Shoot with a session running: xGRC opens and the camera shoots.
- After that, check again whether xGRC appears in Settings › Action Button.

## iPhone: location and Live Activity off at once on End session

After End session on the iPhone, the Dynamic Island still showed the location indicator. `CameraSession.end()` stops geotagging only after the timelapse, the shutter and its camera writes have finished, so Core Location and its `CLBackgroundActivitySession` kept running until then. `SessionCoordinator.endSession` now stops the location source right after it publishes the end, before the teardown, and the teardown stops it again harmlessly. `LiveActivityController.endNow` also ends every xGRC activity, not only the one it tracks.

Device check: start a geotag session, tap End session, and the Dynamic Island clears straight away, with no location indicator and no Live Activity.

## No reconnect after a session ends (2026-10-19)

The maintainer asked that the app never reconnect to the camera after a session ends. Auto reconnect resumes only a session that was interrupted (link drop, app stopped), never one that was ended. Three gaps were closed:

- **OS auto-reconnect left pending.** Connects use `CBConnectPeripheralOptionEnableAutoReconnect`. After a drop, the peripheral reads `.disconnected` while the OS reconnect is still queued, and `CoreBluetoothCentral.cancelConnection` skipped disconnected peripherals. Ending a session during a drop left the OS free to reconnect to the camera later, with no session to use or release it. `cancelConnection` now always calls `cancelPeripheralConnection`, which also stops a pending auto-reconnect.
- **Last session forgotten too late.** `endSession` cleared `lastActiveCameraID` only after the teardown, which can wait on a camera that is gone. If the app stopped during it, the next launch resumed the ended session. It is now cleared before the teardown.
- **A connect overtaken by End session.** `activate` and `pair` wrote `lastActiveCameraID` before installing the session, so a connect that End session overtook still left the camera to resume at launch. It is now written in `install`, once the session is really active. A camera that never connected before the app stopped is therefore not resumed at the next launch.

Test: `SessionLifecycleTests.endWhileReconnecting` (end during a drop cancels the connect, the camera coming back reopens nothing, and launch restores nothing).

Device check: connect, turn the camera off so the app shows Reconnecting, tap End session, turn the camera on. Neither device reconnects, and the camera can pair with another device. Quit and reopen the app: it opens on the camera list.
