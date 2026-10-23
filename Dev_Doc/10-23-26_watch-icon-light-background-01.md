# App icon: lighter background

## Why

App Review rejected 1.0.0 (2) under Guideline 4 (Design). The watch icon's near-black ground (`#0E0F11`) blended into the black watch face, so the icon didn't read as a circle. Apple asked for a lighter background.

## What changed

- The icon keeps the Signal Lens artwork (white lens, amber pin and arcs) and moves to a flat slate ground, `#48586B`, with no gradient. The pin hole is the same colour.
- The watch icon and the main iPhone and iPad icon are the same artwork, rendered from `Design/AppIcon/svg/xGRC-icon.svg`, so the two apps match.
- The iOS 18 dark (transparent ground) and tinted (greyscale on black) variants are unchanged, since the system draws their background.
- Build number raised to 4 (`CURRENT_PROJECT_VERSION` in `project.yml`). Build 3 was archived with an earlier gradient version of the slate ground, so the final icon ships as build 4.

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

The maintainer chose F because it stays closest to the original icon, and asked for the iPhone icon to match it. They then asked for a slightly darker ground with no gradient, and chose the darkest of three flat shades:

| Shade | Ground | Contrast against black |
|---|---|---|
| F1 | `#56677C` | 3.6 : 1 |
| F2 | `#4F6074` | 3.3 : 1 |
| **F3 (chosen)** | `#48586B` | 2.9 : 1 |

For comparison, the rejected `#0E0F11` ground is 1.1 : 1. If App Review flags the icon again, the next step is a lighter ground (F1, or A or C above).

## App Store checks

- 1024 x 1024 px PNG, 8-bit RGB, no alpha, non-interlaced, embedded sRGB profile.
- No mask or rounded corners drawn in; watchOS applies the circle. All artwork sits inside the circle.
- The dark and tinted variants regenerate pixel-identical to the previous files, and the main iPhone PNG is pixel-identical to the watch PNG.

## Device check

After installing build 4, look at the watch home screen (grid and list) and confirm the icon reads as a circle, and check the iPhone home screen in light, dark and tinted modes.
