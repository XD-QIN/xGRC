# xGRC — Product spec

What the app is and how it behaves: why it exists, the fixed product decisions, scope, the camera support matrix, features, and the UI for iPhone, iPad and Apple Watch. How it is built is in the [architecture doc](10-14-26_architecture-02.md); the camera protocols are in the [protocol reference](10-14-26_ble-protocol-reference-03.md); the order of work is in the [phased plan](10-14-26_phased-plan-04.md). The specification has been through seven independent review passes (Apple platform ×3, BLE protocol and camera-maker behaviour ×2, product/architecture ×2); the sources are in the [protocol reference's References](10-14-26_ble-protocol-reference-03.md#references).

## Why

Every camera maker ships a phone app (Creators' App, XApp, Camera Connect, SnapBridge, GR WORLD). They are heavy, slow to connect, drain the battery, and none of them runs on Apple Watch. Hardware remotes (Sony RMT-P1BT, Canon BR-E1, Nikon ML-L7) work well but are one more thing to carry, and they do not geotag.

The [furble](https://github.com/gkoh/furble) project proved that the BLE protocols of Fujifilm, Canon, Nikon, Sony and Ricoh cameras can be reduced to a few GATT writes on an ESP32. xGRC brings that same minimal, robust approach to the devices people already carry, and adds the one thing an ESP32 cannot do well: an always-available, high-quality GPS fix with a great UI.

## Scope

### Fixed product decisions

These are settled and the rest of the document must agree with them.

1. **One camera connected at a time.** Selecting another camera disconnects the current one first.
2. **Every shot is acknowledged** by the camera where the protocol reports it. The app never claims a shot it did not see confirmed; where no confirmation exists it says "sent", never "taken".
3. **Interaction model everywhere:** single tap = focus, double tap = shoot; with a bulb time set, one tap opens a timed bulb. On Apple Watch the hand **Double Tap** gesture is the shutter release.
4. **Release delay** (1–60 s, in Settings): auto-focus, fire, and vibrate once on release.
5. **The watchOS app is fully independent** of the iPhone app.
6. **No HealthKit and no workout sessions.** The watch app is an on-screen task; the only background mechanisms it uses are Core Bluetooth's own background mode (the system keeps the link, watchOS 9+) and a Core Location background session while geotagging.

### In scope

| Area | Detail |
|---|---|
| Platforms | iOS 17+, iPadOS 17+, watchOS 10+ (Swift 6, SwiftUI, Swift Concurrency). Devices with a Dynamic Island (iPhone 14 Pro and later Pro models, iPhone 15 and later non-Pro models; not iPhone 16e) show the Island presentations; every other iPhone and iPad shows the Lock Screen Live Activity. One App Store record: the iOS app plus a watch app marked `WKRunsIndependentlyOfCompanionApp`, so users can install either or both. Watch uploads are built for arm64 with the current watchOS SDK. |
| Transport | Bluetooth Low Energy only, via Core Bluetooth. The app is always the **GATT central**; the camera is the peripheral. |
| Camera control | Focus (half-press), shutter (full-press), timed bulb (1 s–99 min 59 s, one tap), release-delay timer (1–60 s), intervalometer, movie start/stop where the protocol exposes it. One camera at a time, acknowledged shooting (decisions 1 and 2). |
| Geotagging | Periodic location + UTC time push to the camera using each brand's native location-link protocol. Camera writes EXIF itself. |
| Background | **iPhone:** `bluetooth-central` + `location` background modes. A geotag session runs `CLLocationManager.startUpdatingLocation()` with `allowsBackgroundLocationUpdates = true` and `pausesLocationUpdatesAutomatically = false` (so a tripod session is never auto-paused and suspended), inside a `CLBackgroundActivitySession` for the indicator; this is the only thing that keeps the process running. Remote-only use, the intervalometer and the release-delay countdown run with the app in the foreground (keep-screen-on) or while a geotag session is running **and the brand allows remote and geotag in one session** (see the support matrix's background-shooting column). **Watch:** `bluetooth-central` + `location` background modes. Shooting happens with the app on screen; when it leaves the foreground the system keeps the camera link on its behalf (watchOS 9+, Series 6 or later) with a small budget of background wake-ups; a geotag session additionally holds a background location session so pushes continue with the wrist down. No HealthKit. |
| Pairing | Native BLE bonding driven by the system dialogs, plus each brand's application-level registration handshake. On iOS 18+ AccessorySetupKit is used where a brand tolerates the picker pairing on its own connection (Sony); Fujifilm must pair on the app's own connection. Not available on watchOS. |
| Persistence | Paired camera list, per-camera identity secrets, user settings, stored on each device by itself. Phone and watch each have their own complete store; nothing on the watch requires the phone's data. |
| Diagnostics | None in the app (removed 2026-10-16). The GATT transcript stays in memory for development and cannot be exported. |

### Out of scope (for now)

- Image transfer, live view, camera settings (ISO, aperture, etc.). Those need Wi-Fi/PTP and are a different product.
- Android, macOS (macOS may come later for free since Core Bluetooth is shared).
- Bluetooth Classic and MFi External Accessory. iOS does not expose Classic to third parties; Nikon's SnapBridge mode appears to need it (see [Nikon](10-14-26_ble-protocol-reference-03.md#nikon) in the protocol reference), so that mode is a research item that may end up permanently out of scope.
- Controlling several cameras at once (decision 1). furble's "Multi-Connect" is deliberately not carried over.
- HealthKit, workouts, Fitness integration (decision 6).
- Acting as a BLE **peripheral** (e.g. emulating a Bluetooth keyboard volume button to trigger a phone camera). Not needed for real cameras.
- Olympus/OM System, Panasonic, Leica, Hasselblad, Sigma, GoPro, DJI, Pentax K-series. No verified public implementation exists for these (Pentax has only a specification); GoPro has an open BLE spec and could be added later.
- Cross-device sync of any kind in 1.0. A best-effort WatchConnectivity sync of camera *names* (never bonds or secrets) may come later as a separate optional module.

---

## Camera support matrix

"Verified" means the protocol has been confirmed by at least two independent public implementations on the same body class, or by a protocol document plus an implementation. "Single source" means one implementation documents it. "Research" means a working path is not yet known. Nothing has been tested by xGRC yet; this table is the plan, not a result. **Background shooting** means the brand can shoot while a geotag session keeps the app alive in the background; without it, remote use is foreground-only.

| Brand / mode | Pairing | Shutter | Half-press / focus | Bulb (timed) | Movie | GPS geotag | Background shooting | Protocol confidence |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **Sony, α7 IV generation and later** (α7 IV, α7C II, α6700, ZV-E1, α1 II…) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ remote and location link together | **Verified** — alpharemote, GeoShutter, CameraSync (decompiled Creators' App), camera-gps-link (iOS, EXIF confirmed on α7C II), SonyGpsApp, ILCE7M3ExternalGps, furble |
| **Sony, pre-α7 IV bodies** (α7 III, α7R III, α6400, ZV-E10, α1…) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✖ remote **or** geotag per session: Sony's help guides for these bodies state location linkage is unavailable while *Bluetooth Rmt Ctrl* is On | **Verified** — same sources |
| **Fujifilm** secure firmware (22 July 2025 wave onward, and later bodies) | ✅ | ✅ | ✅ | ✅ | ✖ | ✅ | ✅ | **Verified** protocol — furble + GeoShutter + Fujifilm firmware GATT tables (fffw). Pairing, registration and the time packet confirmed on an iPhone (GeoShutter, X100VI 1.32, Sept 2026); EXIF from an iOS geotag not yet confirmed |
| **Fujifilm** legacy firmware (token pairing) | ✅ | ✅ | ✅ | ✅ | ✖ | ✅ | ✅ | **Verified** — furble, Fuji Rumors coverage |
| **Canon EOS — "Remote" mode** (camera pairs us as a BR-E1; camera drive mode must be a self-timer/remote mode) | ✅ | ✅ | ✅ | ✅ | ✅ (needs *Remote control: Enable* for movies) | ✖ (mode has no GPS) | ✖ | **Verified** — furble, canoremote, eos-remote-web, ESP32-Canon-BLE-Remote, Ian Douglas Scott |
| **Canon EOS — "Smartphone" mode** | ✅ | ✅ | ✖ (not exposed) | ✅ | ✖ | ✅ | ✅ | **Two sources** — furble and CanonBLEIntervalometer (EOS M50); they disagree on one mode byte (see Canon section) |
| **Nikon — "Connection to remote" (ML-L7) mode** | ✅ | ✅ | ✖ | ⚠ Time semantics: one press opens, the next press closes | via mode byte | ✖ (mode has no GPS) | ✖ | **Single source** — furble |
| **Nikon — SnapBridge "smart device" mode** | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | — | **Research, likely out of scope** — two implementations (furble; nsg on Z7 II, Z50 II, Z8) agree the camera needs a Bluetooth **Classic** bond on a separate address after the handshake, and SnapBridge on iOS shows the External Accessory picker, which is MFi-only |
| **Ricoh GR IV** | ✅ (passkey) | ✅ (single write) | ✖ (AF runs inside capture) | ✖ | ✅ | ⚠ unverified (furble's GPS path is a stub) | ✅ | **Single source** — furble (GR IV HDF) |
| **Ricoh GR III / IIIx** | ✅ (passkey) | per spec | ✖ | ✖ | per spec | ✅ | ✅ | **Spec + one implementation** — dm-zharov API doc + CameraSync (GR IIIx, GPS and clock); shutter per spec only |

Confirmed-working bodies from the community (all expected to carry over): Fujifilm X-T3/T4/T5, X-T30, X-T200, X-S10/S20, X-E4/E5, X-H1/H2S, X100V/VI, GFX 50S II, GFX 100S/100S II, GFX 100 II, GFX 100RF; Canon EOS M6, M50, RP, R6 Mark II, PowerShot G9 X II; Nikon COOLPIX B600, Z6 III (remote mode); Sony ZV-1F, α1 II, α7 IV, ILCE-6100/6400/6600/6700, 7M3, 7CM2, 7RM3/RM4/RM5, 9, ZV-E10; Ricoh GR IIIx, GR IV.

---

## Features

### Core

- **Scan & add camera.** In the foreground the app scans and classifies advertisements in app code (service UUIDs and manufacturer data) so only cameras show up, with the brand recognised before you tap. Shows the exact camera-side menu steps to enter pairing mode for that brand and generation. If the camera is already bonded to this device by the maker's app, Add-camera detects it, skips pairing mode and warns that the maker's app may hold the camera's lock.
- **Mode: Remote + Geotag, Remote only, or Geotag only (Settings).** Chosen at first launch and changeable any time in Settings; remembered on each device, not synced. The session shows only the pages the mode uses. *Remote only* never asks for location. *Geotag only* starts geotagging as soon as the camera connects and works with the camera's remote function off, which is how Sony bodies older than the α7 IV can be geotagged at all (see [Geotag defaults](10-14-26_architecture-02.md#geotag-defaults)).
- **One active camera.** The Cameras list shows every saved body, but only one is connected at a time. Tapping another camera cleanly disconnects the current one first (location link disabled, every button released) and then connects the new one.
- **Single tap = focus, double tap = shutter; bulb is timed.** One interaction model on every device. A **single tap** on the shutter button sends the half-press (focus); the button shows *focusing*, then *focused* when the camera confirms. A **double tap** sends the full press; the button shows *fired* when the camera confirms. The half-press goes out on touch-down, so there is no recogniser delay and the camera receives its natural half-then-full sequence. Focus stays held for a grace period after a single tap (3 s default) so a later double tap shoots with focus already locked; an **AF hold** toggle keeps it held until the next single tap. **Bulb** is a setting, not a gesture: with a **bulb time** set (Off, or 1 s to 99 min 59 s), one tap opens the shutter, the button counts down the time left, and the shutter closes by itself at zero; a tap during the bulb closes it early. Holding the button never opens bulb. On the watch, **Tap to shoot** (off by default) makes a single tap focus and then shoot, with a haptic on the shot; a hand Double Tap focuses and shoots in either setting (watchOS gives apps the double pinch only, not a single pinch). Exact timings and precedence are in [Gesture timing and precedence](10-14-26_architecture-02.md#gesture-timing-and-precedence).
- **Acknowledged shooting.** Every step waits for the camera's confirmation where the protocol reports it (Sony reports focus and shutter state, Ricoh reports AF and capture status), with a distinct haptic for *focused*, *fired* and *not confirmed*. On cameras whose protocol has no confirmation the app says so and uses a timed press. The counter shows *confirmed* and *sent* separately wherever they can differ. See [Acknowledgement per brand](10-14-26_architecture-02.md#acknowledgement-per-brand).
- **Shutter release delay (Settings).** *Release delay*, off by default, **1 s to 60 s** (slider on phone and iPad, Digital Crown rotation on the watch). When set, any shutter action (double tap, hand Double Tap, intent) starts a visible countdown instead of firing at once. At zero the app **focuses by itself, waits for the focus ack (or the 2 s timeout), sends the full press, and the device vibrates once** when the camera confirms the exposure (or when the full press is sent, on cameras without an ack). A tap during the countdown cancels. Done in the app so it is identical on every brand and on the watch, independent of the camera's own timer menu.
- **Intervalometer** (furble semantics): *count* (1–9999 on iPhone and iPad, up to 9000 on the watch, or infinite), *initial wait*, *shutter-open time* (how long the press is held) and *interval* between frame starts, each in ms / s / min. furble defaults: count 10, interval 15 s, shutter 30 ms, wait 0. Started from its own sheet with a Start button. Cameras with single-write capture (Ricoh) ignore shutter-open time; the UI says so. Rules in [Intervalometer rules](10-14-26_architecture-02.md#intervalometer-rules).
- **Automatic reconnect.** The last-active camera reconnects on its own while a session is active on this device, using the OS pending-connect mechanism; see [Reconnect policy](10-14-26_architecture-02.md#reconnect-policy). "Connect on launch" (launching the app starts a session for the last camera; ending it cancels the pending connect) and "keep trying for the whole session" are settings carried over from furble.
- **Geotag session.** Start/stop. Shows fix quality, time since last push, number of pushes, and the camera's acknowledgement where the protocol has one. Cadence and validity rules are in [Geotag defaults](10-14-26_architecture-02.md#geotag-defaults).
- **Clock sync.** Sends the camera the current UTC time and time zone once per session where the protocol has a time write, so EXIF time and geotag time agree.
- **Live Activity / Dynamic Island (iPhone).** Compact: camera glyph + link dot, GPS state. Expanded: camera name, accuracy and last push, confirmed/sent counter, and one **shutter button** (a `LiveActivityIntent`, runs in the app process) shown only when the active brand supports background shooting; the release-delay countdown when one is running. Lock Screen presentation on devices without a Dynamic Island. On watchOS 11+ the phone's Live Activity also appears in the watch Smart Stack; it is labelled "iPhone · camera" there and carries no shutter button, so it cannot be confused with the watch's own tile.
- **Apple Watch app, standalone.** Installable and usable without the iPhone app. Scan, pair, remote, geotag and settings all live on the watch. Designed as an on-screen task: the Shutter page stays frontmost while you shoot; between visits the system keeps the camera link alive (watchOS 9+ Bluetooth background mode, Series 6 or later), so coming back to the app does not mean reconnecting; a geotag session holds a background location session so pushes continue with the wrist down. Smart Stack tile shows link state. Uses the watch's own GPS (or the phone's when the phone happens to be nearby, which watchOS does automatically).
- **Double Tap to shoot (Apple Watch).** On Series 9, Ultra 2 and newer with watchOS 11+, tapping index finger and thumb together twice fires the shutter while the Shutter page is frontmost, and from the xGRC Smart Stack tile while a session is running. Hands-free release for cold hands, gloves, or when the other hand is holding the camera.
- **Shortcuts and Controls.** App Intents: *Shoot*, *Focus* (half-press held for the grace period), *Start geotagging*, *Stop geotagging*. Every intent returns within 8 s and reports *acknowledged*, *sent* or *not confirmed* in its result dialog; intents apply the release delay only when a geotag session keeps the process alive, otherwise they fire at once and say so. iPhone: the Shoot Control (iOS 18) uses the same `LiveActivityIntent` as the Island button; on iOS 18–25 a separate "Open xGRC" control appears when no session is active, and on iOS 26+ the intent continues into the foreground by itself. Apple Watch: on watchOS 26+ the watch app ships its own Shoot control for Control Center and the Smart Stack; it opens xGRC and shoots there. The Action Button is not supported: watchOS gives it only to workout and similar apps. iPhone controls that appear on the watch run on the iPhone and are labelled "Shoot (phone)", because App Store validation rejects Apple product names in intent and control text (ITMS-90626).
- **iPad.** Same app, sidebar layout; a cable-free studio trigger. Geotagging on iPad needs a cellular (GNSS) model; Wi-Fi-only iPads warn that location accuracy is low.

### Nice-to-have (post-1.0)

- GPX export of the session's own location log (not HealthKit).
- Apple Vision / macOS Catalyst build.
- Optional WatchConnectivity sync of camera names.
- Per-camera "focus with AF-ON" option for Sony back-button-focus users (sends `01 15`/`01 14` instead of the half-press).

### Prior art and competing apps

Third-party apps already do parts of this; they set user expectations and de-risk some spikes. None does all of it, and none combines multi-brand support, acknowledged shooting and an independent watch that geotags on its own.

| App / project | What it proves or offers |
|---|---|
| sMoteWatch, WatchShutter Pro (watch-only, Sony) | A standalone Apple Watch can pair with and drive Sony bodies over BLE: focus, bulb, countdown, intervalometer, video, zoom. The device test pass's watch pairing test can therefore focus on Fujifilm secure and Ricoh. |
| Camera Remote Control Watch (watch-only, BR-E1 modes) | Canon Remote mode on the wrist works. |
| Saschl/alpha-gps (iPhone, open source), Shot Bridge, Geotag Alpha, GeoLink Pro | Sony BLE geotagging in the background on iOS. alpha-gps uses AccessorySetupKit on iOS 18+ and reconnects after the user swipes the app away. Several of the commercial ones are subscriptions; GeoLink Pro also claims Fujifilm. |
| narumiruna/camera-gps-link (iPhone, open source) | Sony location link on Core Bluetooth with EXIF confirmed on an α7C II; includes notes from the Creators' App iOS binary (the `EE01` pairing payload). |
| GRPS, GR Mint, GR Link (iPhone), Ricoh GR WORLD (official, July 2025) | Ricoh GR III/IV geotagging over BLE, including auto-start when the camera powers on. |
| Shutter – Sony / Canon / Fujifilm (Camera Control Apps) | Phone remotes with a watch companion, intervalometer, bulb, bracketing. |
| sarmadjari/GeoShutter | Open-source Kotlin Multiplatform app: Sony (α1 II tested) and Fujifilm secure (X100VI; paired and registered from an iPhone in Sept 2026, EXIF from iPhone geotags still to be checked). Its Fujifilm protocol document and Sony constants are checked against here. |
| rock3r/CameraSync | Android; Sony (α7 IV) and Ricoh GR III/IIIx GPS and clock, with protocol notes decompiled from the Creators' App and GR WORLD. |
| hurui200320/nsg | Nikon Z smart-mode geotagging without SnapBridge (Android, ESP32 with a Classic radio); documents the separate Classic address and bond. |
| robot9706/CanonBLEIntervalometer | Second Canon Smartphone-mode implementation (EOS M50) with a trigger-state notification. |
| tiredboffin/fffw | Fujifilm GATT tables extracted from camera firmware per body and version. |
| Asdoos/SonyGpsApp, narumiruna/sony-geotag, whc2001/ILCE7M3ExternalGps, steven801212/sony-alpha-esp32-gps | Sony location-link implementations the protocol section is checked against. |
| asteppke/ESP32-Canon-BLE-Remote, pklaus/canoremote, RReverser/eos-remote-web | Canon BR-E1 emulation. |

Differentiators xGRC commits to: five brands behind one driver interface, acknowledged shooting with truthful counters, a watch app that needs no phone and geotags on its own, no subscription, and an in-app transcript of every packet for checking a camera's behaviour.

---

## User experience & UI design

Design principles: **glanceable, thumb-first, works with gloves**. Every critical action is one tap or one press. Status is colour + text + haptic, never colour alone.

The visual system is called **Tally**: a dark-first palette with four signal colours (pending, confirmed, location, fault), SF Pro for words and SF Mono for live numbers, a 4 pt grid and glove-sized targets. Its tokens live in code in `Packages/xGRCCore/Sources/DesignKit`, and every screen uses them rather than literal colours or sizes.

### iPhone / iPad screens

```
┌──────────────────────────────┐   ┌──────────────────────────────┐
│ Cameras                   +  │   │ ‹ Sony α7C II          ⚙︎     │
│                              │   │ ● Connected   GPS ● 3 m       │
│ ● Sony α7C II     Connected  │   │                              │
│ ○ X-T5            Saved      │   │   ┌────────────────────┐     │
│ ○ EOS R6 II       Saved      │   │   │                    │     │
│                              │   │   │   (   SHUTTER   )  │     │  ← 140 pt, haptic
│                              │   │   │                    │     │
│                              │   │   └────────────────────┘     │
│                              │   │ tap=focus 2×=shoot           │
│                              │   │ [ AF HOLD ]  Delay 10 s ›    │
│                              │   │ 12 confirmed · 13 sent       │
│                              │   │ [ Intervalometer › ]         │
│  Scan for cameras            │   │  Geotag  ● sending · 8 s ago │
└──────────────────────────────┘   └──────────────────────────────┘

┌──────────────────────────────┐   ┌──────────────────────────────┐
│ Add camera                   │   │ Geotagging                    │
│                              │   │ ┌──────────────────────────┐ │
│ Put the camera in pairing    │   │ │        map (MapKit)       │ │
│ mode:                        │   │ │      · current fix        │ │
│  Sony: MENU → Network →      │   │ └──────────────────────────┘ │
│  Bluetooth → Pairing         │   │ Accuracy        ± 4 m         │
│                              │   │ Last push       6 s ago        │
│ Found                        │   │ Pushes          142            │
│  ◉ α7C II   Sony   -52 dBm   │   │ Interval        5 s   ▾        │
│  ○ X-T5     Fuji   -71 dBm   │   │ Clock sync      done           │
│                              │   │ Live Activity   on             │
│  [ Pair ]                    │   │ [ Stop geotagging ]            │
└──────────────────────────────┘   └──────────────────────────────┘
```

- **Cameras list** — saved cameras with live state (Connected / Connecting / Saved / Busy). Tap to open Remote. Pull-to-refresh rescans. Opening Remote starts a remote session; it ends on the End button, on selecting another camera, or by auto disconnect (see [Reconnect policy](10-14-26_architecture-02.md#reconnect-policy)).
- **Add camera** — brand- and generation-specific pairing instructions above the scan results; results are sorted by RSSI and show the brand badge decoded from the advertisement. The foreground scan stops after 30 s or on leaving the screen.
- **Remote** — the shutter button is the hero. **Single tap** = focus (half-press). **Double tap** = shoot (full press on the second touch-down; the first touch-down already sent the half-press). With a **bulb time** set, one tap opens a timed bulb instead: the disc counts down the time left and the shutter closes at zero; a tap closes it early. The hint line under the button says which applies. Under it: the AF hold toggle, a *Delay* chip showing the release delay and a *Bulb* chip showing the bulb time (tap either to change it in Settings), the *confirmed · sent* counter, and a button to the Intervalometer sheet. With a release delay set, the button shows a countdown ring and the remaining seconds (`Text(timerInterval:)` so it needs no per-second updates), then auto-focuses and fires with a single vibration; any tap cancels. Status strip at the top: link, GPS, camera acknowledgement. The shutter button has five visual states: *idle*, *focusing* (half-press sent, waiting), *focused* (camera confirmed), *fired* (camera confirmed the exposure), *not confirmed* (hollow, with the failure haptic). On a brand without confirmation the *fired* state is always hollow and labelled "sent". On brands with no half-press (Canon Smart, Ricoh, Nikon Remote) a single tap shows "no focus control on this camera" once and the double tap still shoots. On a focus timeout the app shows once: "The camera may be set to back-button AF; enable AF on the shutter button for focus confirmation." There is no alternative layout: the interaction model is the same everywhere (decision 3).
- **Geotagging** — map, numbers, interval. The *Live Activity* switch sets whether the Live Activity is started together with the session (it must be requested while the app is in the foreground; it is then shown when the app backgrounds).
- **Settings** — per-camera: name, mode (Canon Remote vs Smartphone, Nikon Remote vs Smart), geotag interval, Sony keep-camera-awake, forget camera (with the removal checklist, see States & errors); global: **release delay (off, 1–60 s)**, focus grace period, haptics, keep screen on, units, connect on launch, keep trying for the whole session, bulb time (typed as minutes and seconds, up to 99 min 59 s), **auto reconnect** (on by default), **appearance** (System, Light, Dark), and **About** (version, privacy policy, user agreement, developer site, GitHub). There is no Demo camera switch and no diagnostics export (removed 2026-10-16).

### States & errors

Every condition below has a defined UI state, copy and recovery. They are built against `FakeCamera` fault injection in Phase 3.

| Condition | UI state | Copy (short) | Recovery |
|---|---|---|---|
| Bluetooth off or app not authorised | Banner on Cameras | "Bluetooth is off / xGRC needs Bluetooth" | Button to Settings |
| Location denied, Location Services off, or precise location off | Geotag start disabled | "Precise location is needed to geotag" | Button to Settings |
| Low Power Mode (iPhone) | Geotag page note | "Low Power Mode may delay location updates" | — |
| Live Activities disabled for the app | Geotag page note | "Turn on Live Activities for xGRC to see the Island" | Button to Settings |
| Camera powered off / out of range mid-session | Camera row *Connecting…*, Remote button disabled, all buttons released on reconnect | "Looking for α7C II" | Automatic (reconnect policy); after the session window, "Camera off or out of range" |
| Camera asleep while the app still shows Connected | Liveness read before marking Ready after > 60 s idle | "Wake the camera" | One read with timeout; reconnect if it fails |
| Camera busy: connected to another device or the maker's app (Sony `0x9F`, connect timeout while the camera advertises as paired) | Camera row *Busy* | "Linked to another phone, watch or app. Disconnect it there, or turn the camera's Bluetooth off and on." | Retry button |
| Camera already paired with this device by the maker's app | Add-camera detects an existing bond or connection (`retrieveConnectedPeripherals`) | "Already paired with this iPhone. The maker's app may hold the camera's lock while it runs." | Skip pairing mode; connect directly |
| Camera-side feature off (Sony `0x9D` location link off, Sony `FF01` write error `0x90` = *Bluetooth Rmt Ctrl* Off, Fujifilm never asks for location, Canon never sends `0x03`, Ricoh GEO Tag reads `0`) | Page warning | "Turn on Location Info. Link / Bluetooth Rmt Ctrl / Location sync / Store Location Info. on the camera" (brand-specific text) | Link to the brand instructions |
| Sony `0x9D` while the advertisement shows the camera powered off (*Cnct. while Power OFF* on) | Camera row *Off* | "The camera is switched off" | Wait for power-on |
| Sony pre-α7 IV body, geotag requested while *Bluetooth Rmt Ctrl* is On | Modal choice | "This camera turns off Location Link while Bluetooth Rmt Ctrl is On. Use Remote or Geotag for this session." | Instructions to toggle the camera setting |
| Canon Remote: press sent, nothing happened | Hint after first *assumed* shot | "Set the drive mode to Self-timer/Remote (2 s or 10 s); for movies enable Shooting › Remote control" | — |
| Nikon Remote bulb | Standing note on the shutter page | "Bulb runs as Time: set the camera's shutter speed to Time." | — |
| No card or card full (Sony `CC0F`) | Shot reported *not confirmed — no card* | "No memory card / card full" | — |
| Camera battery critical (Sony `CC10`) | Status strip | "Camera battery low" | — |
| Camera in playback or menu, ignoring the shutter | Shot reported *not confirmed* | "The camera did not respond; is it in playback or a menu?" | — |
| No valid GPS fix for 30 s / 60 s | Geotag page amber after 30 s | "No GPS fix — photos untagged" | Keep the keep-alive running; send nothing; Fujifilm requests are left unanswered and logged |
| Link lost after a full press was sent | Shot reported *not confirmed*; counter *sent* increments | "Not confirmed" + failure haptic | Late ack within the window upgrades the shot |
| Watch keeps losing the camera (reduced-range mode after repeated link timeouts) | Watch banner | "Bring the watch closer to the camera. If it keeps failing, turn Bluetooth off and on in Control Centre." | Foreground rescan on disconnect in addition to the pending connect |
| Watch background wake-up budget exceeded | Watch banner | "The watch will keep the camera connected only while xGRC is on screen until you use the app again" | Any user interaction resets the budget |
| GATT changed after a camera firmware update | Remote disabled | "The camera's firmware changed. Forget and pair again." | Handles `didModifyServices` by rediscovering first; only if a characteristic is still missing does it ask to forget |
| Camera forgot us (`peerRemovedPairingInformation`, insufficient authentication on reconnect, or 3 failed registrations); Fujifilm re-paired with XApp on this device (new identity address) | Camera row *Pair again* | "The camera no longer recognises this device. Pair again." | Pairing flow |
| Pairing rejected or timed out on the camera | Pairing sheet error | "The camera did not accept the pairing" | Retry with the brand steps shown again |
| Forget camera | Checklist sheet | "Also remove xGRC on the camera. On iOS 18+ with AccessorySetupKit the app removes the bond; otherwise remove it in Settings › Bluetooth, which also unpairs the maker's app" | Deep link to Settings |
| App force-quit during a session (iPhone) | On next launch | "Session ended because the app was closed" | Onboarding hint: don't swipe xGRC away during a session |

### Dynamic Island / Live Activity

```
Compact (leading | trailing):      Minimal:        Expanded:
┌──────────────────────┐            ┌───┐           ┌──────────────────────────────┐
│ 📷●   …   GPS ±4m 6s │            │📷●│           │ Sony α7C II          ● linked │
└──────────────────────┘            └───┘           │ GPS ±4 m · 6 s · 12 ✓ · 13 ↑  │
                                                    │        [  ◉ Shutter  ]       │
                                                    └──────────────────────────────┘
```

- The Live Activity is requested when a geotag or remote session begins while the app is in the foreground (ActivityKit rule). It can also be started from a `LiveActivityIntent` (Shortcut or Control).
- Updates come from the app process. While a geotag session runs, the background location session keeps the process alive; updates are sent on state change and at most every ~10 s, with `staleDate` set so the system greys the activity out if updates stop. The release-delay countdown uses `Text(timerInterval:)` and the push age uses relative date text, so neither needs per-second updates. Live Activity alerts fire only on countdown release and on failures, never per intervalometer frame.
- The shutter is a `LiveActivityIntent` (iOS 17+), which runs `perform()` in the app process: the press reaches the live BLE link without opening the app. It is shown only when the active brand supports background shooting; on iOS 18–25 with no session, a separate "Open xGRC" control is offered instead; on iOS 26+ the intent declares background and dynamic-foreground modes and continues into the app by itself.
- When the app is backgrounded, a haptic is not guaranteed; the confirmation is delivered as a Live Activity update with an alert configuration, which lights the Island or Lock Screen.
- Limits: static + dynamic content ≤ 4 KB combined; Lock Screen and expanded layouts ≤ 160 pt (two text rows and one button); the system throttles updates; the activity ends after 8 h, after which the Lock Screen copy is stale and its button no longer acts (up to 4 more hours on the Lock Screen). The app re-requests the activity on the next foreground visit or via the intent if the session is still running.
- On watchOS 11+ the phone's Live Activity appears in the watch Smart Stack. xGRC supplies a small supplemental family view labelled "iPhone · camera" with no shutter button, so only the watch's own tile can fire the watch's camera.

### Apple Watch

The watch app is a complete, independent app. It has the same flows as the phone app, laid out for the wrist. The first launch goes straight to *Add camera*; there is no "set up on your iPhone first" step anywhere.

```
 Cameras (root)           Add camera                 Pairing
┌──────────────┐          ┌──────────────┐           ┌──────────────┐
│ Cameras    + │          │ Sony: MENU → │           │ Confirm on   │
│ ● α7C II     │          │ Network →    │           │ camera:      │
│ ○ X-T5       │          │ Bluetooth →  │           │   482 913    │
│ ○ EOS R6 II  │          │ Pairing      │           │ ● Registering│
│              │          │ ◉ α7C II  ▂▄▆│           │              │
│ Scan         │          │ ○ X-T5    ▂▄ │           │ [ Cancel ]   │
└──────────────┘          └──────────────┘           └──────────────┘

 Page 1 – Shutter          Page 2 – Geotag             Page 3 – Settings
┌──────────────┐          ┌──────────────┐           ┌──────────────┐
│ α7C II   ●   │          │ GPS  ● ±5 m  │           │ Camera     › │
│              │          │ Pushed  9 s  │           │ Delay  10 s› │
│   (  ◉  )    │          │ 00:42:17     │           │ Mode       › │
│  12 ✓ · 13 ↑ │          │ ↑ 312 m      │           │ End session  │
│ tap=focus 2× │          │ [ Stop ]     │           │              │
└──────────────┘          └──────────────┘           └──────────────┘
```

- **Pairing on the watch.** The watch scans, shows brand-specific pairing instructions, bonds through the watchOS system dialog and runs the brand's registration handshake, exactly as the phone does. Apple does not document the Bluetooth IO capability the watch presents during pairing; a community packet capture suggests *DisplayOnly*, which would make passkey entry (Ricoh) impossible and downgrade numeric comparison (Fujifilm secure) to Just Works, which MITM-requiring cameras reject. The device test pass (Phase 6) finds out by pairing on the real watch and iPhone (a sniffer capture is optional); "not supported on watch" is an allowed outcome for a brand, recorded in the support matrix. The watch is its own Bluetooth device, so the camera registers it separately from any phone. Camera-side limits from the makers' documentation: **Sony** α bodies: pairing limit undocumented, **only one Bluetooth remote connected at a time** and one location linker at a time (the other must release the `DD30` lock); **Fujifilm** up to 7 paired smartphones/tablets; **Nikon** five smart devices in SnapBridge mode but exactly one remote in ML-L7 mode (pairing the watch as a remote evicts the phone's remote pairing, and the camera's menu selects one connection type at a time); **Canon** one Bluetooth function at a time (Smartphone *or* Remote), so phone-as-smartphone plus watch-as-remote on one Canon body is not possible and the per-camera mode setting must match the camera menu.
- **Runtime model (no HealthKit).** A *remote* session is an on-screen task: shooting happens while the app is active. watchOS returns to the clock after the per-app *Return to Clock* delay (default 2 minutes; onboarding shows how to set xGRC to *After 1 Hour* in Settings › General › Return to Clock › Custom). There is no API to extend frontmost time (the old one was removed in watchOS 7). When the app leaves the foreground, the `bluetooth-central` background mode makes the system **keep the camera link on the app's behalf** (watchOS 9+, Apple Watch Series 6 or later), so returning to xGRC does not require a reconnect; the app gets only a few short background wake-ups per rolling 24 h for camera notifications and disconnects (5 on watchOS 9, shared with background scan grants, reset by user interaction; measured on the real watch in Phase 6), so shooting itself still needs the app on screen, and a brand handshake is never re-run inside a budget wake. On Series 4, 5 and the first-generation SE the link is not kept in the background: a remote session ends when xGRC leaves the screen, and the UI says so. A *geotag* session additionally holds a `CLBackgroundActivitySession` (watchOS 10+) with `allowsBackgroundLocationUpdates`, which Apple lists as a long-running background session; it keeps the process running with the wrist down and after leaving the app, and Core Location relaunches the app after a crash or system termination while the session is outstanding (not after the user quits it). Whether notifications delivered while the location session keeps the app running count against the Bluetooth wake-up budget is unknown; Phase 6 measures it with the real camera, and if they count, watch Fujifilm geotagging sets the camera's sync interval to its maximum (480 s) or is marked foreground-only. The blue location indicator shows while it is active, and Apple documents that the watch shows the app on wrist raise while a background session runs.
- **Controls.** Same model as the phone: **single screen tap on the shutter button = focus**, **double tap = shoot**, and with a bulb time set **one tap = timed bulb**. Implementation: the shutter is a SwiftUI `Button` whose action is *Shoot*, with a plain `ButtonStyle`; a `DragGesture` on the label reports touch-down and touch-up to the shot sequencer, which sends the half-press on touch-down and shoots on the second tap within the double-tap window. (A custom `PrimitiveButtonStyle` replaced the button with a bare view, and Double Tap then fell back to the system's scroll and paging; fixed 2026-10-17.) The hand **Double Tap** gesture performs the control's primary action, which is therefore *Shoot* (the shortcut is declared with `.handGestureShortcut(.primaryAction, isEnabled: selectedPage == .shutter)` so it is enabled only while the Shutter page is selected; on other pages Double Tap keeps its system meaning). If focus is already held from a screen tap, Shoot sends only the full press; otherwise it runs half-then-full itself. During a release-delay countdown Double Tap cancels; during bulb it releases. The system highlights the button when the gesture fires, and the acknowledged-state animation and haptic follow as for a touch. Requirements: watchOS 11 or later and Apple Watch Series 9, Ultra 2 or newer; the modifier is behind an availability check because the minimum is watchOS 10. The Digital Crown is used only by rotation (choosing setting values such as the delay); a Crown press is reserved by the system. The Ultra Action Button is not supported (watchOS gives it only to workout and similar apps).
- **Smart Stack tile.** Shows link state and geotag state. The app writes a small state file into the App Group and reloads the tile only when it would look different, because background reloads are budgeted. While pushes flow the tile shows the session timer; once they stop it shows the push age (relative date text) and turns red after 30 minutes through a scheduled timeline entry. Its *Shoot* button (interactive widgets, watchOS 11+) uses an intent with `openAppWhenRun`, because only the app process holds the camera link: the system opens xGRC and performs the shot **in the app process** (needs a device check, see [the 2026-10-19 review fixes](10-19-26_full-project-review-fixes-01.md)). No intent is forwarded through the App Group. The tile carries `.handGestureShortcut(.primaryAction)` only when its timeline entry says a session is running, so a Double Tap that merely opens the Smart Stack cannot fire the camera.
- **Settings** live on the watch, on the session's Settings page and from the camera list. Every setting with a value opens a screen where the **Digital Crown scrolls through the values** (saved on leaving the screen); on/off settings are toggles. They are: **mode** (Remote + Geotag, Remote only, Geotag only), **release delay (off, 1–60 s, Digital Crown)**, geotag interval, **Tap to shoot**, **bulb time (minutes and seconds on two Crown wheels)**, **auto reconnect**, forget camera, and About. Haptics have no setting; they follow the system's. Nothing is configured "from the phone". With a delay set, a hand Double Tap starts the countdown on the wrist; the watch auto-focuses and fires at zero and plays one haptic on release. **Haptics play only while the app is active (wrist raised, screen awake)**: Apple documents that watch haptics are silently dropped in the background or inactive state, with workout sessions as the only exception (excluded by decision 6). If a countdown ends with the wrist down, the confirmation is shown on the next wrist raise and in the Smart Stack tile, and a local notification (allowed in the background) is the fallback alert.
- **Location.** Core Location on watchOS uses the watch's own GPS when the phone is out of range and the phone's when it is nearby; the app does not care which. Automatic pausing does not exist on watchOS.

### Accessibility

Dynamic Type everywhere, VoiceOver labels on all controls, shutter button reachable by Switch Control. Under VoiceOver a single tap only selects and a double tap activates, so the gesture model cannot be performed literally; the shutter button therefore exposes accessibility actions *Focus*, *Shoot*, *Start/Stop bulb* and *Cancel countdown*, with *Shoot* as the default activate action, and announces state changes ("focused", "fired, confirmed", "sent, not confirmed"). Reduce Motion disables the countdown ring animation. Haptic feedback is distinct for focus-acquired, shutter-fired and not-confirmed. Under AssistiveTouch on the watch, a clench is a single tap (focus); Shoot is reached through the Action Menu (double clench) via the button's accessibility actions. A VoiceOver and AssistiveTouch pass is part of the Phase 6 device test pass.

### Privacy

- No analytics. Crash reports only through Apple (MetricKit / App Store Connect). No network calls of any kind; links the user taps in About open the developer's site or GitHub in the browser, and the map uses Apple Maps. App Store privacy label: *Data Not Collected*; this holds because nothing leaves the device: the transcript cannot be exported, and there is no developer endpoint. If a "report a camera" upload is ever added, the label changes to Coarse Location and Other Diagnostic Data (not linked, not tracking).
- Transcripts contain precise location packets, camera serials and our client UUID. They stay in memory on the device (a bounded ring), are never written to disk and cannot be exported (export removed 2026-10-16).
- Location is used only to send to the connected camera and is never stored beyond the current session's log (which the user can clear).
- Privacy manifests (`PrivacyInfo.xcprivacy`) in all four executables (iOS app, watch app, iOS widgets, watch widgets): tracking false, no collected data types, and one required-reason entry, system boot time (35F9.1), because shot timing uses `ContinuousClock`. No `UserDefaults` or file-timestamp entries: settings are files in Application Support and nothing reads file timestamps.
- Privacy policy: [privacy-policy.md](../privacy-policy.md), hosted at https://xdqin.com/xGRC/privacy-policy; user agreement: [user-agreement.md](../user-agreement.md), hosted at https://xdqin.com/xGRC/user-agreement (decided 2026-10-15).
