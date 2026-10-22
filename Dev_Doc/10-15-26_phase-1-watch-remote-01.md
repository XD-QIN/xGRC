# Phase 1 — Watch remote

Companion to [plan § Phase 1](10-14-26_phased-plan-04.md#phase-1--watch-remote) and the [product spec](10-14-26_product-spec-01.md), [architecture doc](10-14-26_architecture-02.md) and [protocol reference](10-14-26_ble-protocol-reference-03.md). This file records what Phase 1 built, how to install it on the watch, the device tests it adds to the Phase 6 test pass, and what is still open.

**Status (2026-10-15):** code complete. Device testing now happens once, for the whole app, in [Phase 6](10-14-26_phased-plan-04.md#phase-6--device-test-pass); the tests below are Phase 1's part of that list. The shared package compiles and its 31 unit tests pass on a Swift 6.1 toolchain. The watch app, the Core Bluetooth layer and the Keychain store use Apple frameworks and have **not been compiled yet**: the Linux build machine has no Apple SDK. The Core Bluetooth files were type-checked against a stub of the Core Bluetooth API. Expect a few compile fixes on the first Xcode build, which opens the Phase 6 pass. Nothing has run on a watch or a camera yet.

**First driver: Sony.** The camera brand you own was not known when Phase 1 started. Sony was picked because it has the strongest protocol evidence (verified by seven projects) and real shot acknowledgements (`FF02`). Phase 5 adds the other brands' drivers before testing starts. Only the driver changes between brands: the transport, the sequencer, the session and the UI are brand-agnostic.

---

## What was built

### Shared package `Packages/xGRCCore`

| Target | What it contains | Builds without Apple SDK |
|---|---|:---:|
| `BLEKit` | GATT value types (`GATTCharacteristicID`, `Advertisement`, `GATTError`, `LinkEvent`), the `GATTTransport` and `BluetoothCentral` protocols, `withTimeout`, `Broadcaster`, the transcript logger (schema v1, JSON Lines), and `RecordingTransport`, which logs every GATT operation | ✅ |
| `BLEKit/CoreBluetooth` | `CoreBluetoothCentral` and `CoreBluetoothTransport`: one serial queue for the manager and every callback, a restore identifier, pending connects with auto-reconnect, per-characteristic FIFO matching of reads, writes and notify-state changes, and cancellation that keeps the queue slot | ✖ (stub type-checked) |
| `CameraKit` | `CameraDriver`, `ShotScript`, `ShotResult`, `DriverCapabilities`, `DriverRegistry`; **`SonyDriver`**; **`FakeCamera`**, a simulated Sony body behind `GATTTransport` with configurable ack latency and faults; `DemoCentral` | ✅ |
| `SessionKit` | **`ShotSequencer`** (the gesture table on an injected clock), `CameraSession` (link state machine, reconnect, registration backoff), `SessionCoordinator` (one camera at a time: scan, pair, activate, end, forget) | ✅ |
| `Persistence` | `JSONFileStore` (atomic Codable files: `cameras.json`, `settings.json`), `KeychainSecretStore` (`AfterFirstUnlockThisDeviceOnly`, never synchronised), `IdentityStore` for `ClientIdentity` and per-camera `CameraIdentity` | ✅ (Keychain part ✖) |
| `DesignKit` | Tally tokens, from the design work. Left out of the manifest on Linux | ✖ |

### Watch app `Apps/xGRC-watchOS`

- **Cameras** (root): saved cameras with the link dot, a Bluetooth-off banner and *Add camera*. The first launch goes straight to *Add camera*.
- **Add camera**: Sony pairing instructions for both menu generations, a 30-second foreground scan, and the cameras found, marked *Ready to pair* when the advertisement's pairing bits are set.
- **Pairing**: connect, then bond (the system dialog appears when the camera asks), then register (`EE01` once), shown step by step, with *Try again* on failure.
- **Session**, paged vertically:
  - **Shutter**: the link line, the shutter button, the caption, the *confirmed ✓ · sent ↑* counter and a hint line. The button is a `Button` whose action is *Shoot*. A primitive button style reports touch-down and touch-up to the sequencer. Hand Double Tap (watchOS 11+) is enabled only on this page.
  - **Settings**: AF hold, focus hold time (1–10 s), Demo camera, *Export transcript* with the share sheet, *End session* and *Forget camera*.
- Leaving the active scene (wrist down, Return to Clock) sends `sceneInactive`, which releases every held button.
- Haptics come from DesignKit's `ShutterAppearance`: focused, fired, not confirmed.

### Watch widget extension `Apps/xGRC-Widgets-watchOS`

A shell Smart Stack tile that opens the app. Link state and the *Shoot* button arrive in Phase 3.

### Project

`project.yml` is an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. The `.xcodeproj` is generated, not committed, so the project never drifts from the folder layout.

---

## How the pieces fit

```
watch UI ──touchDown/touchUp/shoot──▶ SessionCoordinator ──▶ CameraSession ──▶ ShotSequencer
                                                                  │                   │ ShotScript steps
                                                                  │                   ▼
                                                     link events ◀┤            SonyDriver ── FF02 events ──┐
                                                                  ▼                   │ writes             │
                                                    RecordingTransport (transcript) ◀─┘                    │
                                                                  ▼                                        │
                                                CoreBluetoothTransport  or  FakeCamera (demo, tests) ──────┘
```

- **Acknowledged shooting.** A shot is *acknowledged* only when `FF02` reports `02 A0 20` inside the window our own press opened. Otherwise it is *unconfirmed* (ack timeout or link lost), and a late ack within 10 s upgrades it. *Failed* means nothing went out. The counter shows *confirmed* and *sent* separately.
- **Sony shot order:** `01 07` half-down, then `01 09` full-down, the shutter ack, `01 08` full-up and `01 06` half-up. A double tap with focus already held skips the second half-press. *Shoot* with nothing held waits up to 2 s for the focus ack, then fires anyway.
- **Bulb:** a long press (500 ms) holds `01 09` until the next tap, with a 30-minute cap. *(Replaced after Phase 5 by the timed bulb: with a bulb time set, one tap opens it and it closes by itself; see [Gesture timing and precedence](10-14-26_architecture-02.md#gesture-timing-and-precedence).)*
- **After every reconnect** the driver re-subscribes `FF02`, then every button is released before anything else.
- **Errors with copy:** ATT `0x90` means *Bluetooth Rmt Ctrl* is Off, `0x9F` means another device holds the camera, and a removed bond or insufficient authentication on reconnect shows *Pair again*.

---

## Departures from the spec, now reflected there

1. **Executor rule.** BLEKit confines its state to one serial `DispatchQueue`, the same queue Core Bluetooth calls back on, instead of actors on a custom executor. The guarantee is the same: one thread of control for all radio state, and only value snapshots leave BLEKit. Bridging `NSObject` delegates into actors adds hops without adding safety.
2. **`ShotScript` fields.** The spec listed `single`, `latch` and `unlatch`. The sequencer composes shots from `focusPress`, `focusRelease`, `shootFromFocus`, `shootWithoutFocus`, `latch`, `unlatch` and `releaseAll`. That is what lets a double tap skip the second half-press, and lets *Shoot* add the focus wait itself.
3. **Driver API.** `CameraButton` replaces `Button`, which clashes with SwiftUI. Drivers also gain `send(_:)`, which serialises one script write, and `events()` / `linkEvents()` are functions that return a fresh stream per caller. The location-link calls are left out until Phase 2.
4. **Watch-only target for now.** With no iOS app yet, the watch target is `WKWatchOnly`. Phase 4 adds the iOS app and switches it to `WKRunsIndependentlyOfCompanionApp`. It stays fully independent at runtime.
5. **Timeouts** are applied by callers with `withTimeout`, not by the transport: a 60 s bonding window for the first protected access, 5 s per write and 10 s for discovery. This relies on the transport's cancellation rule.

---

## Build and install

1. On the Mac (Xcode 16 or later): `brew install xcodegen`, then run `xcodegen generate` in the repository root.
2. In `Config/Local.xcconfig` (git-ignored; format in `Config/Signing.xcconfig`), set `DEVELOPMENT_TEAM` and a bundle-ID prefix you own (`XGRC_BUNDLE_PREFIX`).
3. Open `xGRC.xcodeproj`, pick the `xGRC-watchOS` scheme and your watch, then Run.
4. The package tests run anywhere: `cd Packages/xGRCCore && swift test`.
5. Watch settings: *Settings › General › Return to Clock › xGRC › After 1 Hour*.
6. Sony camera settings: *Bluetooth Function* On, *Bluetooth Rmt Ctrl* On, then *Pairing* from the menu while the watch is on *Add camera*.

Without a camera: turn on *Demo camera* in Settings (or pair the *Demo α7 IV* from *Add camera* after turning it on). It runs the real Sony driver against a simulated body.

---

## Device tests (run in Phase 6)

These run during the [device test pass](10-14-26_phased-plan-04.md#phase-6--device-test-pass), together with the later phases' tests. Record each result in `docs/support/sony-<model>.md` using the [template](#support-record-template) below, and note every problem in the pass's issue list. This is the plan's watch-remote list, made concrete for Sony.

| # | Test | How | Record |
|---|---|---|---|
| 1 | Pairing dialog | Pair from the watch with the iPhone app absent and the phone's Bluetooth off | Dialog type (Just Works / numeric comparison / passkey); whether the camera accepted it; whether `EE01` was written (transcript) |
| 2 | 100 shots | Double tap 100 times at a normal pace | Counter must read `100 ✓ · 100 ↑` with no stuck button. Any *not confirmed* gets its transcript lines |
| 3 | Shot order | Export the transcript after one double tap | `FF01` writes are `01 07`, `01 09`, `01 08`, `01 06`; `FF02` has `02 3f 20` and `02 a0 20` |
| 4 | Focus ack | Single tap with AF on the shutter button, then with back-button AF | Focus ack present or absent; the hint appears in the second case |
| 5 | Timed bulb | Camera in Bulb, bulb time 5 s, one tap; then bulb time 60 s, tap, tap again after about 10 s | First exposure about 5 s, closed by itself; second about 10 s, closed by the tap; counter +1 each |
| 6 | Rmt Ctrl off | Turn *Bluetooth Rmt Ctrl* Off, shoot | Message "Turn on Bluetooth Rmt Ctrl on the camera"; transcript shows ATT `0x90` |
| 7 | Leave the app | Press the crown; come back after 2, 5 and 10 minutes | Does the link survive without a reconnect (no `link` lines in the transcript)? Any budget notes? |
| 8 | Wrist down | Return to Clock set to 1 h; shoot, lower the wrist, raise it | Shutter page still up; haptic only while the screen is awake |
| 9 | Range | Walk away until the link drops, come back | Reconnect time from the transcript; does *Camera off or out of range* appear after 60 s? |
| 10 | Camera off and on | Switch the camera off mid-session, then on | Reconnects without user action; first writes after reconnect are `01 08`, `01 06` |
| 11 | Connection interval | — | Not visible to apps. Note it from a PacketLogger capture on the Mac if you take one (optional) |

### Phase 6 bars for this part

- [ ] 100 acknowledged shots on the watch, zero stuck states
- [ ] The link survives leaving the app for 10 minutes, or the reason it does not is written down
- [ ] Pairing dialog type, reconnect time and negotiated connection interval are in the support record
- [ ] The exported transcript opens in a text editor and shows the whole pairing and a shot

### Support record template

```markdown
# Sony <model> — <firmware>
Watch: <model>, watchOS <version>. xGRC <version>. Date: <yyyy-mm-dd>.

| Item | Result |
|---|---|
| Advertisement byte 4 (protocol version) / byte 9 (flags) | |
| Pairing dialog on the watch | |
| EE01 needed at first pairing | |
| 100-shot run: confirmed / sent / stuck | |
| Focus ack with shutter-button AF / back-button AF | |
| Link after leaving the app 2 / 5 / 10 min | |
| Reconnect time after range loss | |
| Rmt Ctrl Off → ATT 0x90 | |
| Connection interval (optional) | |

Transcript: `<file>.jsonl`
```

---

## Not in Phase 1 (later build phases)

- Geotagging, `LocationKit`, Sony `DD30`/`DD31`/`DD11` and the Geotag page (Phase 2).
- Release delay, intervalometer, the Smart Stack tile's *Shoot* button, every error state's copy, the foreground rescan on disconnect (Phase 3).
- The iOS app, Live Activity, Controls and Shortcuts (Phase 4).
- Other brands (Phase 5).
- Testing on the watch and camera (Phase 6).

## Known gaps

- **Foreground rescan on disconnect.** The spec asks for one on the watch as well as the pending connect. Phase 1 has only the pending connect; Phase 3 adds the rescan.
- **`CC09` parsing.** It is read and logged, not decoded; remote availability comes from the `FF01` result.
- **Busy detection** relies on ATT `0x9F`, which Sony documents for the location lock only. Whether a second remote gets the same error is a test-1 observation in Phase 6.
- **The privacy policy URL and the licence choice** are not code; the plan now places them in Phase 4. (Both were settled on 2026-10-15: Apache 2.0 at first, GPLv3 since 2026-10-21, and a privacy policy hosted at https://xdqin.com/xGRC/privacy-policy.)
