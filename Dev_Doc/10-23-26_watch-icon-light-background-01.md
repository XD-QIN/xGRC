# Watch icon: lighter background

## Why

App Review rejected 1.0.0 (2) under Guideline 4 (Design). The watch icon's near-black ground (`#0E0F11`) blended into the black watch face, so the icon didn't read as a circle. Apple asked for a lighter background.

## What changed

- The watch icon keeps the Signal Lens artwork (white lens, amber pin and arcs) and moves to a slate gradient ground, `#6E8299` at the top to `#4A5A6E` at the bottom. The pin hole takes the ground's colour at that height, `#4F6074`.
- New vector source `Design/AppIcon/svg/xGRC-watch-icon.svg`; the watch PNG in `Apps/xGRC-watchOS/Assets.xcassets/AppIcon.appiconset` is rendered from it.
- The iOS and iPadOS icons are unchanged.
- Build number raised to 3 (`CURRENT_PROJECT_VERSION` in `project.yml`) so the fixed build can be uploaded.

## Options considered

Six colour-only variants of the same artwork, each previewed as a circle on black at 300, 84, 60 and 42 px:

| Option | Ground | Lens | Pin | Arcs |
|---|---|---|---|---|
| A Paper | `#F4F4F2` | `#0E0F11` | `#F59E0B` | `#F59E0B` |
| B Amber | `#FFB020` | `#0E0F11` | `#FFFFFF` | `#0E0F11` |
| C Amber glow | `#FFC94A` to `#FF8A00` | `#FFFFFF` | `#0E0F11` | `#FFFFFF` |
| D Silver | `#FFFFFF` to `#D3D5D9` | `#1C1E22` | `#F59E0B` | `#1C1E22` |
| E Cream | `#FFEFC8` | `#0E0F11` | `#F08C00` | `#F08C00` |
| **F Slate (chosen)** | `#6E8299` to `#4A5A6E` | `#F4F4F2` | `#FFB020` | `#FFB020` |

The maintainer chose F because it stays closest to the original icon. It is the darkest of the six, so if App Review flags it again, the next step is a lighter ground (A or C).

## App Store checks

- 1024 x 1024 px PNG, 8-bit RGB, no alpha, non-interlaced, embedded sRGB profile.
- No mask or rounded corners drawn in; watchOS applies the circle. All artwork sits inside the circle.
- Regenerating the iOS icons from the same generator gives pixel-identical files, so only the watch icon changed.

## Device check

After installing build 3, look at the watch home screen (grid and list) and confirm the icon reads as a circle.
