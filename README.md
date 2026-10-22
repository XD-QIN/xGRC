# xGRC — Bluetooth Camera Remote & GPS Geotagger for iPhone, iPad and Apple Watch

xGRC is a native iOS, iPadOS and watchOS app that talks directly to the **built-in Bluetooth Low Energy interface of mirrorless and compact cameras**. No dongle, no Wi-Fi, no maker app.

It does two things:

1. **Remote shutter.** Focus, shoot, timed bulb, release delay and intervalometer, from the phone, the iPad or the wrist.
2. **GPS geotagging.** Streams the device's location and UTC time to the camera, which writes GPS EXIF into every photo. On iPhone it runs in the background and shows in the Dynamic Island; on Apple Watch it works with the phone left at home.

> **Status:** code complete for Phases 1–5 (watch remote and geotag, watch polish, iPhone/iPad app, all five brands), proven against simulated cameras in package tests. Next is the on-device test pass (Phase 6), then beta and 1.0 (Phase 7). See the [phased plan](Dev_Doc/10-14-26_phased-plan-04.md).

## Why

Every camera maker ships a phone app. They are heavy, slow to connect, drain the battery, and none runs on Apple Watch. Hardware remotes work but are one more thing to carry, and they do not geotag. The [furble](https://github.com/gkoh/furble) project showed that these cameras' BLE protocols come down to a few GATT writes; xGRC brings that minimal approach to the devices people already carry and adds a good GPS fix and a good UI.

## Features

- **One interaction model everywhere:** single tap focuses, double tap shoots; with a bulb time set (up to 99 min 59 s), one tap opens a timed bulb that closes by itself. On the watch, *Tap to shoot* makes one tap focus and shoot.
- **Acknowledged shooting:** the app says *fired* only when the camera confirms it, and *sent* where the protocol has no confirmation.
- **Release delay** (1–60 s) and an **intervalometer** with furble's semantics.
- **GPS tracks:** every session that geotags keeps its fixes with their times on the device, one CSV per session named by its start time (`2026-10-21-09-54-36.csv`). Each remote shot is a row too (`shot` column 1). Shown on a map on iPhone and iPad, fixes blue and shots orange; exported as CSV from either device or the watch.
- **Three modes**, chosen in Settings: Remote + Geotag, Remote only, or Geotag only.
- **Standalone Apple Watch app:** scan, pair, shoot and geotag without the iPhone. Hand **Double Tap** fires the shutter on Series 9, Ultra 2 and later.
- **Live Activity and Dynamic Island** on iPhone, with a shutter button where the brand allows background shooting.
- **Shortcuts and Controls:** Shoot, Focus, Start and Stop geotagging.
- **Auto reconnect** (on by default): reconnects when the link drops and reopens the last session at launch; **auto disconnect** after an idle timeout (default 15 minutes).
- **Light, dark or system appearance** on iPhone and iPad.
- **Thirteen languages**, the same as xMosaique: English (the default), Chinese (Simplified and Traditional), Spanish (Spain and Latin America), Portuguese (Brazil), French, German, Italian, Japanese, Korean, Hindi and Indonesian, chosen in Settings › Language on each device.

The full feature and UI definition is in the [product spec](Dev_Doc/10-14-26_product-spec-01.md#features).

## Supported cameras

| Brand / mode | Shutter | Focus | Timed bulb | Geotag | Confidence |
|---|:---:|:---:|:---:|:---:|---|
| Sony α / ZV / RX / FX with *Bluetooth Rmt Ctrl* | ✅ | ✅ | ✅ | ✅ | Verified |
| Fujifilm X and GFX (secure and legacy pairing) | ✅ | ✅ | ✅ | ✅ | Verified |
| Canon EOS / PowerShot, *Remote* mode | ✅ | ✅ | ✅ | ✖ | Verified |
| Canon EOS / PowerShot, *Smartphone* mode | ✅ | ✖ | ✅ | ✅ | Two sources |
| Nikon, ML-L7 remote mode | ✅ | ✖ | Time semantics | ✖ | Single source |
| Ricoh GR III / IIIx / IV | ✅ | ✖ | ✖ | ✅ (GR III/IIIx) | Spec + one implementation |

Nothing has been tested on a real body by xGRC yet. Sony bodies older than the α7 IV can use the remote or geotagging per session, not both. Nikon SnapBridge mode needs Bluetooth Classic and is likely out of scope. The full matrix, with sources and community-confirmed bodies, is in the [product spec](Dev_Doc/10-14-26_product-spec-01.md#camera-support-matrix).

## Requirements

- iOS / iPadOS 17+, watchOS 10+ (Apple Watch Series 6 or later for background link keeping).
- Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build. Swift 6, SwiftUI, Swift Concurrency.

## Build and run

```sh
brew install xcodegen
xcodegen generate          # creates xGRC.xcodeproj from project.yml (not committed)
open xGRC.xcodeproj
```

1. Create `Config/Local.xcconfig` (git-ignored) with your `DEVELOPMENT_TEAM` and a bundle-ID prefix you own (`XGRC_BUNDLE_PREFIX`); `Config/Signing.xcconfig` shows the format. Never put them in `project.yml`.
2. Pick the `xGRC-iOS` or `xGRC-watchOS` scheme and your device, then Run.

The package tests run on a Mac or on Linux:

```sh
cd Packages/xGRCCore && swift test
```

Per-brand camera setup and install notes are in the [Phase 1](Dev_Doc/10-15-26_phase-1-watch-remote-01.md#build-and-install) and [Phase 5](Dev_Doc/10-15-26_phase-5-other-brands-05.md) docs.

## Repository layout

```
xGRC/
├── Apps/                 iOS/iPadOS app, independent watchOS app, widget extensions, shared app code
├── Config/               Signing.xcconfig (placeholders); your Local.xcconfig stays untracked
├── Packages/xGRCCore/    BLEKit, CameraKit (drivers), LocationKit, SessionKit, Persistence, SharedState, DesignKit
├── Design/               Tally design-system canvas boards and the app icon sources
├── Dev_Doc/              developer docs (below)
├── AppStorePreview/      App Store screenshots and the tools that make them
├── App_Store_Intro/      App Store listing copy and review notes
├── project.yml           XcodeGen spec
├── LICENSE               GNU General Public License v3.0
├── privacy-policy.md     privacy policy (hosted at xdqin.com/xGRC/privacy-policy)
└── user-agreement.md     user agreement (hosted at xdqin.com/xGRC/user-agreement)
```

The module-level layout is in the [architecture doc](Dev_Doc/10-14-26_architecture-02.md#repository-layout).

## Developer docs

Everything beyond this overview lives in [`Dev_Doc/`](Dev_Doc):

| Doc | What it holds |
|---|---|
| [Product spec](Dev_Doc/10-14-26_product-spec-01.md) | Fixed product decisions, scope, support matrix, features, UI for iPhone, iPad and Apple Watch, states and errors, privacy |
| [Architecture](Dev_Doc/10-14-26_architecture-02.md) | Modules and key abstractions, gesture timing, intervalometer, reconnect and geotag rules, acknowledgement per brand, Apple platform constraints, budgets, testing, open risks |
| [BLE protocol reference](Dev_Doc/10-14-26_ble-protocol-reference-03.md) | Per-brand GATT layouts and byte sequences (Sony, Fujifilm, Canon, Nikon, Ricoh) and every source used |
| [Phased plan](Dev_Doc/10-14-26_phased-plan-04.md) | Phases 1–7, work items, the Phase 6 device test list and exit criteria |
| [Phase 1](Dev_Doc/10-15-26_phase-1-watch-remote-01.md) · [2](Dev_Doc/10-15-26_phase-2-watch-geotag-02.md) · [3](Dev_Doc/10-15-26_phase-3-watch-polish-03.md) · [4](Dev_Doc/10-15-26_phase-4-iphone-ipad-app-04.md) · [5](Dev_Doc/10-15-26_phase-5-other-brands-05.md) | What each build phase built, its decisions, known gaps and its device tests |
| [Sony vs AlphaRemote](Dev_Doc/10-15-26_sony-alpharemote-review-06.md) | The Sony driver compared with AlphaRemote, and the bulb bug it found |
| [Watch gestures and settings](Dev_Doc/10-16-26_watch-gestures-and-settings-01.md) · [Double Tap fix](Dev_Doc/10-17-26_watch-double-tap-fix-01.md) | Watch gesture, settings and Double Tap rounds |
| [GPS track log](Dev_Doc/10-21-26_gps-track-log-02.md) | Per-session GPS tracks: recording, the CSV format, the map and export |
| [Localization](Dev_Doc/10-21-26_localization-03.md) | The thirteen languages, the in-app language setting, the string catalogs and how to add a string |
| [Full review fixes](Dev_Doc/10-19-26_full-project-review-fixes-01.md) | Every finding of the 2026-10-19 code review, its outcome, and the device test checklist |
| [Open-source release](Dev_Doc/10-21-26_open-source-gplv3-04.md) | The move to GPLv3, the fresh public history and what was kept out of it |

Code comments cite these as *product spec §*, *architecture doc §* and *protocol reference §* followed by the section name. The design-system boards are indexed in [`Design/README.md`](Design/README.md).

**Naming convention.** Every file in `Dev_Doc/` is named `MM-DD-YY_what-was-done-NN.md`: the date the work was done, a short kebab-case description, and a two-digit counter that starts at `01` for the first doc of that day and counts up for each further doc the same day (for example `10-15-26_phase-1-watch-remote-01.md`, then `10-15-26_phase-2-watch-geotag-02.md`). Apart from this README, the only Markdown files at the repository root are the privacy policy and the user agreement.

## Acknowledgements

The camera protocols were reverse-engineered by the open-source community. xGRC builds on [gkoh/furble](https://github.com/gkoh/furble) above all, and on the projects listed in the [protocol reference's References](Dev_Doc/10-14-26_ble-protocol-reference-03.md#references). furble is MIT-licensed and is referenced, not copied.

## Legal

- [Privacy policy](privacy-policy.md), published at <https://xdqin.com/xGRC/privacy-policy>. xGRC collects no data: location goes only to your camera over Bluetooth, and there are no accounts, analytics or servers.
- [User agreement](user-agreement.md), published at <https://xdqin.com/xGRC/user-agreement>.

xGRC is not affiliated with, endorsed by, or supported by Sony, Fujifilm, Canon, Nikon, Ricoh or Apple. Brand and product names are trademarks of their owners. Use at your own risk; a broken pairing can usually be fixed by deleting the device on the camera and in Settings → Bluetooth.

## License

xGRC is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License](LICENSE) as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [LICENSE](LICENSE) file for details.
