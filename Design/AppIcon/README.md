# xGRC app icon: Signal Lens

Chosen 2026-10-15: concept 4 (Signal Lens) with an amber location pin in the lens.

Colours: slate gradient ground `#6E8299` to `#4A5A6E` (pin hole `#4F6074`), with the Tally ring `#F4F4F2` and amber pin and arcs `#FFB020`. The ground was near-black `#0E0F11` until 2026-10-23, when App Review rejected it because the watch icon didn't read as a circle on the black watch face; the iPhone and iPad icon moved to the same ground so the two match. See [the icon background doc](../../Dev_Doc/10-23-26_watch-icon-light-background-01.md).

| Path | Use |
|---|---|
| `AppIcon.appiconset/` | iOS/iPadOS app icon, single 1024 px size, with iOS 18 dark (transparent background) and tinted (greyscale) variants. In the repo at `Apps/xGRC-iOS/Assets.xcassets/AppIcon.appiconset`. |
| `WatchAppIcon.appiconset/` | watchOS app icon, single 1024 px size. watchOS applies the round mask. In the repo at `Apps/xGRC-watchOS/Assets.xcassets/AppIcon.appiconset`. |
| `svg/` | Vector sources for each variant (1024 px canvas, 100-unit viewBox). `xGRC-icon.svg` is the main icon for iPhone, iPad and watch. |

The main PNGs are opaque (no alpha), as App Store Connect requires.
