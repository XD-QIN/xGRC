# Watch sheets: readable close button

Date: 2026-10-29. On the watch, the close button at the top left of the
first-launch tips was a white cross on a white disc.

## Cause

The watch app tints everything with `Tally.Palette.textPrimary`, near-white,
so that colour stays for status signals (board 01 · Rules). The system close
button of a sheet takes that tint for its disc, while its cross stays white.
The Timelapse sheet had the same button.

## Change

- `SheetCloseButton.swift` adds `sheetCloseButton(action:)`, a
  cancellation-action toolbar button that replaces the system one: a
  semibold white cross on `Tally.Palette.raised`, with "Close" as its
  VoiceOver label (localized in all thirteen languages).
- The tips sheet (`OnboardingView`) is wrapped in a `NavigationStack` so it
  has a toolbar; the Timelapse sheet already had one.
- Behaviour is unchanged: the cross only dismisses. Closing the tips without
  finishing them still shows them again at the next launch.

## Device check

On the watch, first launch (or Settings › Show tips again) and Timelapse:
the cross is white on a dark grey disc and closes the sheet.
