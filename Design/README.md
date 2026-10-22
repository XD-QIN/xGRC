# Design — Tally design system

Source of the "xGRC Design System" canvas: the visual reference for the tokens in [`Packages/xGRCCore/Sources/DesignKit`](../Packages/xGRCCore/Sources/DesignKit). When the two disagree, the Swift code is what ships; update the canvas to match.

| Board | File | Contents |
|---|---|---|
| 01 · Color | `Main.dc.html` | Dark and light ground, text colours with contrast ratios, the four signal colours and their meanings, colour rules |
| 02 · Type, space & shape | `Type.dc.html` | SwiftUI text styles and monospaced readouts, 4 pt spacing, corner radii, glove-sized targets, haptics and motion |
| 03 · Shutter button | `Shutter.dc.html` | Gesture model and the six acknowledged-shooting states (interactive), release-delay countdown, bulb |
| 04 · Status & feedback | `Status.dc.html` | Camera link states, status strip, confirmed/sent counter, banners from product spec § States & errors, controls, voice |
| 05 · iPhone · Remote | `Phone.dc.html` | The Remote screen built from the tokens |
| 06 · Apple Watch | `Watch.dc.html` | Shutter, Geotag and Settings pages |
| 07 · Dynamic Island & Lock Screen | `Island.dc.html` | Compact, minimal and expanded Island, Lock Screen Live Activity, watch Smart Stack tiles |

The shared controls drawn on boards 04 and 07 (buttons, status chips, the AF HOLD chip, the confirmed · sent counter and banners) are in `DesignKit/TallyControls.swift`; the shutter's disc labels, bulb and countdown drawing are in `Apps/Shared/App/ShutterButton.swift`.

`canvas.json` holds the board layout. Each `.dc.html` file is a Design Component page: it needs the canvas runtime (`support.js`) to render, so opening one directly in a browser shows unstyled template markup. To view or edit the boards, open them in the Design canvas they came from.
