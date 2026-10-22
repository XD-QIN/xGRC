# Watch Tap to shoot: more taps become photos

Date: 2026-10-21. Built on the review-fixes round, whose `ShutterButton` touch handling this keeps.

## Problem

After a field test, the maintainer reported that *Tap to shoot* on the watch (one tap focuses, then shoots) "does not work very well". The exact symptom is not known yet, so this round fixes the ways a tap could be lost or mis-read on the code path.

## Causes found

1. **A small slide cancelled the shot.** A lift more than 12 pt from where the finger came down counted as a scroll: focus was released and nothing fired. A finger on a moving wrist, wet or gloved, often drifts that far during a tap.
2. **Taps during a shot were dropped.** While a shot was going out (half-press, waiting for focus, full press, release), a new tap did nothing. A camera slow to focus made this window long, so a second tap felt ignored.
3. **Touch order was not guaranteed.** Each touch-down and touch-up went to the camera session in a task of its own, with several hops on the way. Nothing guaranteed a quick tap's lift could not get there before its touch-down. If it did, the touch-down then held the half-press with no lift to come, and the next tap only shot.

## Fix

- `Apps/Shared/App/ShutterButton.swift`: a lift counts as a tap when it ends on the disc or within 24 pt of its edge (`liftsOnShutter`). Only a lift well off the shutter, or a touch the system takes for a scroll, releases focus without shooting. `ShutterDisc.size` is now a static so the button can measure against it.
- `Packages/xGRCCore/Sources/SessionKit/ShotSequencer.swift`: with Tap to shoot on, a tap made while a shot is in flight is kept (one at most) and fires when that shot finishes. A finger still down when the shot finishes shoots on its lift. A tap that slides off adds nothing. A failed shot drops the kept tap, and so do a link loss and leaving the app. Bulb mode is unchanged.
- `Apps/Shared/App/AppModel.swift`: shutter inputs go through one ordered stream and one task, so they reach the sequencer in the order they happened.

## Follow-up: the hand Double Tap

The maintainer then said the trouble was the hand Double Tap (index finger and thumb), not taps on the screen. Two more ways that gesture lost a photo:

1. **Double Tap during a shot was dropped.** *Shoot* while a shot was in flight did nothing. Now it is kept (one at most) and fires when that shot finishes, like a tap with Tap to shoot.
2. **Double Tap while the link came back scrolled the page.** Raising the wrist after a while often finds the watch reconnecting to the camera for a moment. The shutter was disabled then, so watchOS had no control for Double Tap and did its own scroll and paging instead, which could move the Shutter page off screen. Now, while the link is connecting or reconnecting, the shutter stays dimmed and ignores screen touches but still takes Double Tap. The shot is held and goes out as soon as the camera is ready, if that is within 5 s. Otherwise the watch says no photo was taken and plays the failure haptic. A busy, failed or ended link drops it.

Files: `ShotSequencer.swift` (`queuedShot`, dropped when a bulb closes), `AppModel.swift` (`isLinkReturning`, `holdShot()`), `ShutterButton.swift` (`holdsShot`, `ShutterButtonStyle(dimmed:)`), `xGRC-watchOS/SessionView.swift`. Test: `shootDuringShot`.

Still outside the app's control: with the screen dimmed (wrist down), watchOS ignores Double Tap until the wrist is raised.

The focus wait itself is unchanged. On a brand that confirms focus (Sony), the shot waits up to 2 s for it; brands without a focus ack wait 250 ms.

## Tests

`ShotSequencerTests`: a tap during a slow-focusing shot is the next shot; a finger still down when the shot ends shoots on its lift; a touch during a shot that slides off adds no shot.

## Device checks

- Tap to shoot on: quick taps, each one a photo, including taps made while the previous shot is still going out.
- A tap that drifts a little still shoots. Sliding well off the shutter does not shoot and releases focus.
- Tap to shoot off: one tap focuses, two quick taps shoot, as before.
- Double Tap twice quickly: two photos.
- Lower the wrist for a few minutes, raise it and Double Tap at once: the photo is taken when the link is back, and the page does not scroll.
