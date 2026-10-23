# xGRC app icon: Signal Lens

Chosen 2026-10-15: concept 4 (Signal Lens) with an amber location pin in the lens.

Colours are from the Tally design system: ground `#0E0F11`, ring `#F4F4F2`, pin and arcs `#FFB020`.

The watch icon uses a lighter slate ground instead (gradient `#6E8299` to `#4A5A6E`, pin hole `#4F6074`), chosen 2026-10-23 after App Review rejected the dark ground because the icon didn't read as a circle on the black watch face. See [the watch icon doc](../../Dev_Doc/10-23-26_watch-icon-light-background-01.md).

| Path | Use |
|---|---|
| `AppIcon.appiconset/` | iOS/iPadOS app icon, single 1024 px size, with iOS 18 dark (transparent background) and tinted (greyscale) variants. In the repo at `Apps/xGRC-iOS/Assets.xcassets/AppIcon.appiconset`. |
| `WatchAppIcon.appiconset/` | watchOS app icon, single 1024 px size. watchOS applies the round mask. In the repo at `Apps/xGRC-watchOS/Assets.xcassets/AppIcon.appiconset`. |
| `svg/` | Vector sources for each variant (1024 px canvas, 100-unit viewBox). `xGRC-watch-icon.svg` is the watch icon. |

The main PNGs are opaque (no alpha), as App Store Connect requires.
