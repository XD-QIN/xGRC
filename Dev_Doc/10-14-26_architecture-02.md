# xGRC — Architecture

How xGRC is built: the module structure, the key abstractions and timing rules, the Apple platform constraints that shape the design, budgets, testing strategy, repository layout and open risks. What the app does is in the [product spec](10-14-26_product-spec-01.md); the per-brand GATT details are in the [protocol reference](10-14-26_ble-protocol-reference-03.md).

## Architecture

### Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Apps (SwiftUI)                                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────┐ │
│  │ iOS / iPadOS app     │  │ watchOS app          │  │ Widget exts    │ │
│  │ + App Intents        │  │ + App Intents        │  │ (Live Activity,│ │
│  │   (in-process)       │  │   (in-process)       │  │  Smart Stack)  │ │
│  └──────────┬───────────┘  └──────────┬───────────┘  └───────┬────────┘ │
└─────────────┼─────────────────────────┼──────────────────────┼──────────┘
              │                         │        read-only TileState.json   
┌─────────────▼─────────────────────────▼──────────────────────┼──────────┐
│  SessionKit  (actors)                                        │          │
│  SessionCoordinator (one CameraSession) · ShotSequencer ·    ▼          │
│  GeoTagStreamer · Intervalometer · LiveActivityController ·  App Group  │
│  WatchRuntimeController · ReconnectPolicy · ShutterService              │
└───────┬───────────────────────────┬──────────────────────────┬──────────┘
        │                           │                          │
┌───────▼──────────┐   ┌────────────▼───────────┐   ┌──────────▼──────────┐
│  CameraKit       │   │  LocationKit           │   │  Persistence        │
│  CameraDriver    │   │  LocationSource        │   │  Codable stores     │
│  protocol +      │   │  (CoreLocation),       │   │  Keychain secrets   │
│  drivers:        │   │  FixFilter, Rate-      │   │  (per device, no    │
│  Sony, Fujifilm, │   │  Limiter, UTCClock     │   │  cross-device dep.) │
│  Canon×2, Nikon×2│   └────────────────────────┘   └─────────────────────┘
│  Ricoh, Fake     │
└───────┬──────────┘
        │
┌───────▼──────────────────────────────────────────────────────────────────┐
│  BLEKit — async wrapper over Core Bluetooth (single serial executor)     │
│  CentralManager · Peripheral · GATT cache · state restore ·              │
│  AdvertisementParser · Transcript logger · CoreBluetoothMock in tests    │
└──────────────────────────────────────────────────────────────────────────┘
```

Everything above the app layer is a **Swift Package** (`Packages/xGRCCore`) with targets `BLEKit`, `CameraKit`, `LocationKit`, `SessionKit`, `Persistence`. Both apps depend on the same package. `CameraKit` has **no Core Bluetooth import**; it talks to a `GATTTransport` protocol so drivers are unit-testable with recorded transcripts.

**Process rule:** only the app processes link `BLEKit` and own a `CBCentralManager`. App Intents are compiled into the app targets so they run in-process; the widget-target copy of an intent calls a `CameraIntentHandler` protocol the app registers at launch and never links `BLEKit` (widgets link only the Foundation-only `SharedState` target). Widget extensions read a `TileState.json` snapshot (well under 2 KB, atomic write) from the App Group and never open the store or touch Bluetooth. On iOS, the Island button and the iOS 18 Control both use `ShootLiveActivityIntent` (a `LiveActivityIntent`, compiled into app and widget targets), which the system performs in the app process. On watchOS the Smart Stack tile's and the Shoot control's *Shoot* and *Focus* declare `openAppWhenRun`, so the system opens xGRC and performs them in the app process (since 2026-10-17; needs a device check). In the app process *Shoot*, *Focus* and *Start geotagging* are also `ForegroundContinuableIntent`s.

**Executor rule:** `BLEKit` owns one serial `DispatchQueue`, used as the `CBCentralManager` queue; every delegate callback runs on it, and `CoreBluetoothCentral` / `CoreBluetoothTransport` touch their mutable state only on it (queue confinement, so the classes are `@unchecked Sendable`; public async methods hop onto the queue with a continuation). This gives the same single thread of control as actors on a custom executor without bridging `NSObject` delegates into actors. `CBPeripheral` and `CBCharacteristic` never leave `BLEKit`: only value snapshots (`UUID`, `Data`, enums) and the `GATTTransport` protocol do. The central is created synchronously in the app delegate's launch method with a constant restore identifier (scene-based apps receive no launch options), and `LocationSource` re-creates the background location session at launch when a session record is open.

### Key abstractions

```swift
/// What a driver needs from the radio. Implemented by BLEKit (real) and by test fakes.
protocol GATTTransport: Sendable {
    func discover(services: [UUID]) async throws -> [GATTService]       // services, characteristics, properties
    func read(_ chr: GATTCharacteristicID) async throws -> Data          // forbidden on a characteristic the driver has subscribed to
    func write(_ data: Data, to chr: GATTCharacteristicID) async throws  // with response
    func writeWithoutResponse(_ data: Data, to chr: GATTCharacteristicID) async throws   // awaits peripheral readiness
    func subscribe(_ chr: GATTCharacteristicID) async throws -> AsyncThrowingStream<Data, Error>  // resolves after didUpdateNotificationState; ends with an error on link loss
    func properties(of chr: GATTCharacteristicID) async -> CharacteristicProperties
    func maximumWriteLength(withResponse: Bool) async -> Int             // Core Bluetooth has no MTU request API
    func readRSSI() async throws -> Int
    func linkEvents() -> AsyncStream<LinkEvent>                          // a fresh stream per caller: .reconnected .disconnected(reason, isReconnecting)
                                                                         // .servicesModified .bondRemoved .backgroundBudget(exceeded:)
    func disconnect() async
}
/// GATTCharacteristicID = (service UUID, characteristic UUID): Fujifilm reuses one characteristic UUID in two services.
/// Errors: enum GATTError { case att(UInt8), insufficientAuthentication, peerRemovedPairing, disconnected(LinkReason), timeout,
///                          characteristicNotFound, bluetoothUnavailable, readOnSubscribedCharacteristic, other }
/// Cancellation rule: an awaited operation that is cancelled returns at once but keeps its queue slot until Core Bluetooth calls
/// back or the link drops; Core Bluetooth cannot cancel an in-flight ATT request and its callbacks carry no request ID.
/// Timeouts are applied by callers with `withTimeout(_:_:)` (bonding window 60 s, write 5 s, discovery 10 s), relying on this rule.
/// BluetoothCentral (scan, connect with autoReconnect/timeout, connectedPeripherals, cancelConnection) is the other BLEKit protocol;
/// CoreBluetoothCentral implements it, and CameraKit's DemoCentral serves the simulated camera.

/// One camera brand/mode. Pure protocol logic, no timing policy. Every driver is an actor (it holds state).
protocol CameraDriver: Actor {
    static var descriptor: DriverDescriptor { get }           // id, brand, capabilities, ack source
    static func matches(_ adv: Advertisement) -> CameraMatch? // decode manufacturer data / service UUIDs (foreground scan)
    init(transport: any GATTTransport)

    /// First pairing on a camera found by scan. Returns the identity to persist (token, serial, generated IDs).
    func pair(_ adv: Advertisement, client: ClientIdentity, progress: @Sendable (PairingStep) -> Void) async throws -> CameraIdentity
    /// Every connect after pairing, including every OS auto-reconnect: re-subscribe, re-register, re-enable.
    func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws
    func disconnect() async                                   // disable location link, release every button, drop the link

    func press(_ button: CameraButton) async throws -> PressOutcome // .sent or .unsupported; .focus .shutter .movie
    func release(_ button: CameraButton) async throws               // (CameraButton, not Button: SwiftUI owns that name)
    func send(_ write: ShotWrite) async throws                       // one script write, serialised with minimumWriteGap
    nonisolated var shotScript: ShotScript { get }                  // brand's step lists and quirks (below)

    nonisolated var geotagRules: GeotagRules { get }          // fix age (Sony 10 s, others 30 s), minimum interval, send vs fix time
    func startLocationLink() async throws -> LocationLinkMode    // .push or .pull; Sony DD30/DD31, Canon 0x01 after 0x03, Ricoh GEO Tag
    func stopLocationLink() async                             // never throws: always tries to release the lock
    nonisolated var keepAlive: KeepAlivePolicy? { get }       // Sony CC02 every 9 s; executed by GeoTagStreamer, not the driver
    func syncClock(_ time: Date, zone: TimeZone) async throws // no-op where the protocol has none
    func updateLocation(_ fix: GeoFix, time: Date, zone: TimeZone) async throws   // zone: Sony's standard offset and DST
    // Drivers without .geotag keep the protocol extension's defaults (throw .unsupported).

    nonisolated func events() -> AsyncStream<CameraEvent>     // fresh stream per caller: .focusAcquired .focusLost .shutterActive .shutterReady .captureStatus
                                                              // .locationRequested .locationEnabled(Bool) .cardStatus .battery …
}

/// Brand press/release recipe as a step list the sequencer executes. Examples:
///   Sony:      write(01 07) · awaitAck(.focus, 2 s, optional) · write(01 09) · awaitAck(.shutter, 3 s) · write(01 08) · write(01 06)
///              (half-down, full-down, full-up, half-up — alpharemote, CameraSync/Creators' App, GeoShutter, furble's lock path)
///              bulb toggles: latch = write(01 09) · awaitAck(.shutter, 3 s) · write(01 08) · write(01 06); unlatch = write(01 07) · write(01 09) · write(01 08) · write(01 06)
///   Fujifilm:  write(01 00)+write(03 00) · write(01 00)+write(02 00) · hold(100 ms) · write(01 00)+write(00 00) (one release ends both)
///   Canon R:   write(0x4C) · write(0x8C) · hold(100 ms) · write(0x0C)            (combined control byte; with response where the camera allows)
///   Ricoh:     write(flavour 0) · write(01 01) · awaitAck(.capture, 3 s)         (single-write capture, no half-press)
///   Nikon R:   write(02 02) · hold(100 ms) · write(02 00); bulb = Time: the same press/release opens, the next closes
enum ShotStep { case write(ShotWrite), awaitAck(AckKind, timeout: Duration, optional: Bool), hold(Duration) }   // ShotWrite marks the write that fires
struct ShotScript {
    let focusSupported: Bool
    let focusPress, focusRelease: [ShotStep]          // touch-down; end of the grace period
    let shootFromFocus: [ShotStep]                    // full press, shutter ack, full release (focus held around it)
    let shootWithoutFocus: [ShotStep]                 // whole shot for brands without a half-press
    let latch, unlatch: [ShotStep]                    // timed bulb: open on one tap, close at zero or on the next tap
    let releaseAll: [ShotStep]                        // every button up: after reconnect, on scene change
    let minimumWriteGap: Duration
}
/// The sequencer composes: double tap with focus held = shootFromFocus + focusRelease (no second half-press);
/// Shoot with nothing held = focusPress + awaitAck(.focus, 2 s, optional) + shootFromFocus + focusRelease.

enum FocusResult { case acquired(Duration), timedOut, unsupported }

/// Every shot reports how it was confirmed. The UI and the intervalometer branch on this.
enum ShotResult {
    case acknowledged(focusLatency: Duration?, shutterLatency: Duration)   // camera reported the exposure
    case assumed(heldFor: Duration)                                        // protocol has no report; timed press used
    case unconfirmed(UnconfirmedReason)                                    // press sent, but ack timed out or link lost
    case cancelled
    case failed(ShotError)                                                 // write error before the press went out
}

struct DriverCapabilities: OptionSet {
    static let halfPress, bulb, bulbAsTime, movie, geotag, geotagPull, clockSync, backgroundShooting
    static let cameraSelfTimer                         // camera-side timer (Ricoh 2 s flavour); not part of the gesture model
    static let ackFocus, ackShutter, ackLocation      // which confirmations the camera can give
}
```

- **`CameraIdentity`** is the per-camera identity the driver needs to reconnect, returned by `pair()`: Fujifilm legacy → 4-byte token; Fujifilm secure → 5-byte serial; Nikon → `device`+`nonce` IDs and the camera serial; Canon and Sony → nothing beyond the bond (Canon Smart stores *our* client UUID and name camera-side). Stored in Keychain, keyed by camera record ID. Records also store the last `CBPeripheral.identifier` (iOS never exposes the MAC address).
- **`ClientIdentity`** is *our* identity as seen by cameras: a display name (`xGRC-xxxxx`, like furble's `furble-xxxxx`) and a 128-bit client UUID. furble derives both from the chip MAC so they never change; xGRC generates them once per device and keeps them in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and `kSecAttrSynchronizable = false`, so iCloud Keychain never gives phone, iPad and watch the same identity. Keychain items normally survive reinstalling, but Apple does not guarantee it; a changed identity means re-pairing on Canon Smart and Nikon, and the Forget-camera checklist is shown after a reinstall.
- **`SessionCoordinator`** (actor) holds at most one `CameraSession` (decision 1). Switching cameras is `disconnect(current) → connect(next)`, never two links at once. A session is *active* from Start (opening Remote, starting geotag, or launch with "connect on launch") until End, camera switch, 5 minutes after leaving Remote with no geotag session, or app termination; auto-reconnect exists only inside an active session.
- **`CameraSession`** (actor) owns the state machine `idle → scanning → connecting → bonding → registering → ready → {remote, geotag} → disconnected`, the per-camera serial command queue, and the rule that every OS reconnect runs `driver.reconnect()` before any queued command.
- **`ShotSequencer`** owns all timing: gestures, acks, grace period, countdown, cancellation. It is brand-agnostic and executes the driver's `shotScript`. Its clock is injected (`any Clock<Duration>`) so tests are deterministic. Defined in [Gesture timing and precedence](#gesture-timing-and-precedence).
- **`GeoTagStreamer`** merges `LocationSource` fixes with driver capabilities and runs the driver's `keepAlive` policy. Defined in [Geotag defaults](#geotag-defaults).
- **`Intervalometer`** (actor) runs furble's four-state loop on the injected clock. Rules in [Intervalometer rules](#intervalometer-rules).
- **`LiveActivityController`** / **`WatchRuntimeController`** are the platform glue: the first owns `Activity<SessionAttributes>` on iOS; the second owns the `CLBackgroundActivitySession` on watchOS and watches for `CBError.Code.leGattNearBackgroundNotificationLimit` / `.leGattExceededBackgroundNotificationLimit` in the characteristic-update callback's error (watchOS 9+) so the UI can say when the system will stop keeping the link. Each is a no-op on the other platform.
- **`ShutterService`** is the protocol App Intents call; the app registers the real implementation at launch, and widget-target copies of intents resolve it through dependency injection.
- **Transcript logger**: every GATT op (direction, UUID, bytes, latency, error) goes to an in-memory ring buffer only (no OSLog) (no export since 2026-10-16; see Privacy). Transcript schema v1 is JSON Lines: `t`, `op`, `service`, `char`, `props`, `bytes`, `attError`, `linkEvent`, plus a header with OS, device, MTU and app version. This is how we will verify protocols on bodies we do not own.

### Gesture timing and precedence

| Input | Sequencer action | Values |
|---|---|---|
| Touch-down on shutter button | `press(.focus)` immediately, **unless** latched, counting down, or focus already held (then no write) | — |
| Single tap (no second touch-down within the window after first touch-up) | Keep focus held for the grace period, then `release(.focus)` | double-tap window 300 ms from first touch-up; grace 3 s default (settable 1–10 s) |
| Double tap | Full press on the **second touch-down**; no second half-press; then `awaitAck(.shutter)` and release per `shotScript` | shutter ack timeout 3 s |
| Focus ack | Waited for only in the release-delay and intent paths; a double tap never waits for it | focus ack timeout 2 s |
| Focus ack timeout | Full press is still sent; result reported truthfully (`.unconfirmed(.focusTimedOut)` if the shutter ack also fails); one-time back-button-AF hint | — |
| Touch held | Nothing more than the touch-down: focus stays held; no bulb | — |
| Tap in bulb mode (bulb time set, camera has bulb) | Release delay first if set; then `focusPress` + focus wait (brands with half-press) + `latch`; the bulb countdown starts when the shutter is open and `unlatch` runs at zero | bulb time Off or 1 s–30 min (setting); Ricoh and other cameras without bulb ignore it |
| Tap while latched | `unlatch` steps now (closes the bulb early); no new focus press. Nikon Remote and Sony: the bulb toggles, so `unlatch` is a second press/release (`unlatchToggles`); on Sony it is sent only if the opening press drew the shutter ack | — |
| AF hold on | Single tap toggles: press focus, or release it if already held | — |
| Tap to shoot on (watch setting, off by default) | Touch-down sends `press(.focus)` as usual; touch-up shoots at once: the focus ack of that touch's own half-press (or the brand's settle time), then the full press and release. No double-tap window, no grace period; the release delay still applies. A shot without a camera ack plays its own *released* haptic | focus ack timeout 2 s |
| Release delay set | Countdown first; at zero `press(.focus)` → focus ack or 2 s → full press → shutter ack → release; one haptic on the shutter ack (or on send without ack). A first-tap half-press is held through the countdown and released by the sequence | 1–60 s |
| Tap during countdown | Cancel: release every button, report `.cancelled` | — |
| Hand Double Tap (watch) | Performs *Shoot* (a timed bulb in bulb mode); during countdown = cancel; during bulb = unlatch | enabled only on the Shutter page or the Smart Stack tile while a session runs |
| Scene leaves active during bulb or countdown (watch Return to Clock, app backgrounded with no geotag session) | Release every button, report `.cancelled` | — |
| Burst in continuous drive | One press; counter +1 sent, +1 confirmed on the first shutter ack | — |
| Link lost mid-press or mid-bulb | Report `.unconfirmed(.linkLost)`; the first action after reconnect is `release` of every button | — |
| Late ack | A shutter ack within the late-ack window after an `.unconfirmed` upgrades that shot and fixes the counter | min(10 s, intervalometer interval − 100 ms) |
| Camera-originated events | Acks are matched only inside the window opened by our own press; others are logged as camera-initiated | — |
| Brands without half-press | `press(.focus)` returns `.unsupported`; single tap shows the one-time hint; double tap = plain press/release (Ricoh: single write) | — |

The same values are mirrored in the `FakeCamera` tests in Phase 1.

### Intervalometer rules

- Interval is **start-to-start**; if a frame overruns, the next starts at once and the overrun is logged.
- Release delay never applies to intervalometer frames; use *initial wait*.
- Frames send the full press only, with no AF, unless *AF each frame* is on (then each frame runs the focus step with its 2 s timeout).
- On cameras with a shutter ack, the next frame waits for *shutter ready*, at most interval + 5 s, so a slow card write delays a frame instead of dropping it.
- While disconnected the run pauses and frames are skipped (counted *missed*), not failed; it stops with a haptic after 3 consecutive failures with the link up.
- Counter = *sent* (all presses, including assumed) and *confirmed* (acknowledged); reset on session start.
- Shutter-open time above 1 s is executed as bulb (`latch`, hold, `unlatch`: press, hold, release on most brands; press, wait, press again on Sony and Nikon, whose bulb toggles); on a non-Bulb camera that is a burst in continuous drive, or two photos on a toggling brand, and the sheet says so.
- On iPhone the run needs the app in the foreground or a geotag session on a brand with background shooting; the Start button says so when neither holds. On the watch the run needs the app on screen (or a geotag session on such a brand).

### Reconnect policy

- The reconnect target is only the **last-active camera** of the active session on this device. Ending the session releases the camera and cancels any pending connect, so the phone in a pocket does not steal the camera from the watch in the user's hand.
- **Static-address brands** (Sony, Canon, Ricoh, Fujifilm legacy): OS pending `connect()` with `CBConnectPeripheralOptionEnableAutoReconnect` (iOS 17 / watchOS 10, so always available). The app implements the disconnect callback with the `isReconnecting` flag and never calls `connect` again while it is true. No app polling.
- **Resolvable-private-address brands** (Fujifilm secure, Nikon): after bonding, Core Bluetooth resolves the address with the camera's identity key, so the `CBPeripheral.identifier` stays stable and the pending connect works, but it only completes when the camera powers on or wakes and advertises (Fujifilm advertises for about 6–10 s after power-on and stops about 30 s after losing a link). A watch additionally runs a foreground rescan on disconnect, because watchOS reduces its reconnection range after repeated link timeouts and Apple's engineers recommend rescanning there. Fallback: foreground scan matched by serial (Fujifilm) or device ID (Nikon).
- **Auto disconnect** (Settings, Digital Crown on the watch: Never, 5–60 minutes, **15 by default**). The session ends by itself after that long connected with nothing done on the camera, or that long without reaching it. Shots, intents, starting geotag or a timelapse, and changing the mode count as use; geotagging, a running timelapse, a countdown or an open bulb count for as long as they run, so the idle time starts when they end. No link for the whole time ends the session even while geotagging, since nothing reaches the camera. Ending cancels the pending connect and releases the location lock; the camera list says why the session ended, with a notification if the app is not on screen.
- **Timeouts.** The 30 s connect timeout applies only to the first connect while pairing. Reconnects are pending connects bounded by the session: 60 s, or the whole session with *Keep trying*. Encryption failures on reconnect ("Failed to encrypt the connection", reported by GeoShutter on Fujifilm) are retried 3×.
- **Every OS reconnect runs `driver.reconnect()`** (subscriptions, registration, Sony `DD30`/`DD31`, Fujifilm status/name/sync interval) before any queued command, only while the app is running (foreground or location session), never inside a watch budget wake.
- **Registration failures** (the camera connected but rejected the app-level handshake): backoff 2 / 4 / 8 s, three tries, then the *Pair again* state. *Pair again* also appears on `peerRemovedPairingInformation` and on insufficient authentication after a reconnect; a camera that is merely off shows "Camera off or out of range".
- **Fujifilm watchdog** (from GeoShutter's measured behaviour; **not built yet**, the general reconnect policy covers silent connections for now, [Phase 5 doc](10-15-26_phase-5-other-brands-05.md#decisions-and-defaults)): if the camera sends nothing within 15 s of setup, redo the setup on the same link; after another 15 s, reconnect. The camera may also end the connection that follows one the phone closed, so a disconnect right after `disconnect(current)` is expected and retried once.
- **Background rediscovery limits:** a background scan matches only advertised service UUIDs; manufacturer-data-only advertisements (Sony, Nikon-paired) cannot be found by a background scan and rely on the pending connect. Recorded per brand in the support table whether a service UUID is advertised after pairing.

### Geotag defaults

| Rule | Value |
|---|---|
| Location source | `CLLocationManager.startUpdatingLocation()`, `desiredAccuracy = kCLLocationAccuracyBest`, `activityType = .otherNavigation`, `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false` (iOS; the property does not exist on watchOS), inside a `CLBackgroundActivitySession` for the indicator. `CLLocationUpdate.liveUpdates()` is **not** used: its stationary auto-pause can suspend the app on a tripod |
| Push interval, all push drivers (Sony, Canon Smart, Nikon Smart, Ricoh) | 5 s default, configurable per camera, Ricoh minimum 10 s; also on movement, where a movement trigger needs ≥ 10 m beyond the fix's horizontal accuracy (never 1 m: that is below GPS jitter) |
| Pull model (Fujifilm) | Camera's sync interval: the driver writes 10 s on every connect, secure and legacy (not a setting yet); on a watch that proves to spend its wake-up budget on notifications, 480 s |
| Fix validity | Position, date and time valid and no older than 30 s (furble's rule); **Sony 10 s**, matching Sony's own app behaviour as observed by SonyGpsApp, which also stops sending after 60 s without a fix |
| No valid fix | Send nothing, keep the keep-alive running, amber "No GPS fix — photos untagged" after 30 s; Fujifilm requests are left unanswered and logged |
| Accuracy gate | Horizontal accuracy ≤ 50 m default; never replace a recent good fix with one more than 3× worse within the validity window |
| Altitude | `CLLocation.altitude` (mean sea level, what EXIF expects; furble's GGA altitude is MSL too), never `ellipsoidalAltitude` |
| Timestamp | **Send time** in UTC for Sony, Fujifilm, Canon Smart (the fix is at most 30 s old); **fix time** for Ricoh and Nikon Smart, whose protocols define it as acquisition time |
| Fujifilm monotonic rule | Each answer must carry a timestamp strictly newer than the previous one (the camera is reported to drop otherwise); send time guarantees it, and an answer that would not be newer is skipped and logged |
| Enable sequence | `startLocationLink()` once at session start (Sony `DD30`/`DD31` where present, Canon Smart `0x01` after the `0x03` request, Ricoh GEO Tag `A36AFDCF` read, then write `1` only after the user confirms); re-checked only when the camera notifies a change. `stopLocationLink()` on session end always writes Sony `DD31` ← 0 then `DD30` ← 0 so another phone or watch can take the lock |
| Keep-alive (Sony) | `CC02` auto-power-off avoidance every 9 s, **off by default** because it keeps the camera's screen on; the camera keeps using its last fix for about a minute and re-takes location about 10 s after it wakes and reconnects. The per-camera *Keep camera awake* switch turns it on for sessions where the first shots after wake must be tagged |
| Sony remote vs geotag | On pre-α7 IV bodies the camera disables location linkage while *Bluetooth Rmt Ctrl* is On; the session is Remote or Geotag. Until verified model codes exist the user picks *Geotag only* in Settings and the Geotag page says so; the modal, keyed on the model code in the advertisement, comes after Phase 6, with the advertisement's location-enabled bit (byte 9 bit 4) logged for the support table |
| Background (iPhone) | Only during a geotag session; permission *While Using* only |

### Data

Three small Codable stores (`CameraRecord`, `SessionLog`, `Settings`) in the app's **private** container on each device independently, written atomically; SwiftData is not used (its App Group + extension sharing invites the `0xdead10cc` suspension-with-lock termination during long background sessions, and three models do not need it). Secrets in Keychain (`kSecAttrAccessibleAfterFirstUnlock` so background reconnects work; `ThisDeviceOnly` and non-synchronizable for identities). Widgets read only `TileState.json` in the App Group. The watch and the phone each own a complete store; the watch never depends on the phone's data, and bonds and per-camera identities are per device by design (a camera registers the watch and the phone as two separate clients). The `Persistence` module has no WatchConnectivity dependency.

### Concurrency & safety

- Swift 6 strict concurrency. Core Bluetooth delegate callbacks run on `BLEKit`'s single serial executor (see the executor rule); no delegate object escapes `BLEKit`.
- Every driver write is serialised per peripheral with the script's `minimumWriteGap` (deterministic ordering for multi-write commands like Fujifilm's `[01 00]` then `[02 00]`).
- All timeouts are explicit (`pair` connect 30 s, bonding 60 s user window, per-write 5 s, Nikon handshake stage 10 s, focus ack 2 s, shutter ack 3 s; the Fujifilm watchdog's 15 s is not built yet).

### What xGRC takes from furble, and what it replaces

furble's `lib/furble` (drivers) and `src/` (application) were read in full at commit `0cac22a`. This is the mapping.

| furble | What it does | xGRC equivalent |
|---|---|---|
| `Camera` base class + `shutterPress/Release`, `focusPress/Release`, `updateGeoData` | The four shutter primitives and one geotag entry point every driver implements | `CameraDriver.press(_:)` / `release(_:)` with the same two buttons, plus `updateLocation` |
| `CameraList::match` chain (FujifilmBasic → CanonSmart → CanonRemote → Nikon → Ricoh → Sony → FujifilmSecure) | Advertisement classification, de-duplicated by address | `DriverRegistry.match(adv)` in the same order on foreground scans; de-duplicated by peripheral identifier *and* by serial/device ID |
| `serialise/getSerialisedBytes` + NVS index keyed by address | Per-camera persisted identity | `CameraIdentity` in Keychain, `CameraRecord` in a Codable store, keyed by a stable record ID with the last peripheral identifier stored separately |
| `Device::init` (RPA own address, ENC+ID key distribution, name `furble-xxxxx`, MAC-derived UUID) | Our BLE identity | `ClientIdentity` in Keychain; address privacy and key distribution are handled by the OS |
| `Camera::connect` security setup (bonding + MITM + Secure Connections; IO capability *display-yes/no*, *keyboard-display* for Ricoh) | Pairing method selection | Not settable on Apple platforms; the OS's IO capability (undocumented; observed in Phase 6) and the camera's decide the dialog |
| `Control` task: state machine, serialised connects, per-target command queue, fan-out, infinite-reconnect | Session orchestration | `SessionCoordinator` with exactly one `CameraSession`; fan-out and Multi-Connect dropped on purpose; infinite reconnect kept as a setting |
| `GPS` task: NMEA parse, 1 s service timer, 30 s max age, fix-quality gate, GPS UTC as time source | Location source | `LocationSource` over Core Location with the same validity rules plus an accuracy gate |
| `Fujifilm::m_GeoRequested` flag serviced by the 1 s loop | Answer the camera's pull within ≤ 1 s | Answer directly in the notification handler from the cached fix |
| `Sony::locationEnabled()` reading `DD30`/`DD31` before every push | Ensure location link is enabled | `startLocationLink()` once at session start; re-check only on a `DD01` notification |
| `Ricoh` 10 s / movement throttle, `validTimesync` range checks | Rate limit and sanity checks | Same rules, shared by all push drivers |
| `Ricoh` "location control" write to `9111CDD0` | Enable geotag (furble's assumption) | Not written: the documented geotag switch is GEO Tag `A36AFDCF` in the Camera service; `9111CDD0` is identified by CameraSync as the WLAN security type |
| Intervalometer (`count`, `delay`, `shutter`, `wait`; idle → wait → shutter-open → delay → finished) | Timelapse | `Intervalometer` actor, same parameters; interval redefined as start-to-start |
| Shutter lock (focus-held + shutter, or long-press) | Bulb / hold | Timed bulb: one tap opens, closes at the bulb time |
| Settings: Auto-Connect, Infinite-ReConnect, Multi-Connect, GPS on/off | User options | Connect on launch, keep trying and GPS carried over; Multi-Connect dropped (single camera); TX power, GPS baud, themes, touch calibration are hardware-specific and dropped |
| `FauxNY` fake camera | UI testing without hardware | `FakeCamera` driver, which also emits acks, and injects faults; tests only, no Demo camera in the app since 2026-10-16 |
| `Scan` (active scan, continuous window) | Discovery | Foreground `scanForPeripherals` with app-side classification, stopped after 30 s; background relies on pending connects |

### Deliberate departures from furble

furble's protocol work is the foundation of this project. Its *application* logic was written for an ESP32 with two buttons and no operating-system services, and in the places below xGRC intentionally does something different. Each item names what furble does (verified against its source), what xGRC does, and why.

| # | furble does | xGRC does | Why |
|---|---|---|---|
| 1 | **Fire-and-forget shutter.** Never subscribes to Sony's `FF02` status. It subscribes to Ricoh's capture status and Fujifilm's NOT1 but only logs or stores them; no shot ever waits on them. | Every driver subscribes to whatever confirmation the camera offers at connect time and the sequencer waits for it. A shot is *acknowledged*, *assumed* (no ack in the protocol), *unconfirmed* or *failed*, never silently "done". | Users must be able to trust the counter and the haptic. The intervalometer must not drop frames while the camera is busy. |
| 2 | **Sony shutter without half-press.** The shutter button alone writes only `01 09` / `01 08`; the half-press pair is only sent through the shutter-lock path when focus is held (which releases full before half). | Every Sony shot runs half-down → full-down → shutter ack → full-up → half-up: the order used by alpharemote, CameraSync (from the decompiled Creators' App) and GeoShutter. freemote's README lists half-up before full-up and is the outlier. | Sony expects the half-press frame; sources agree the camera can get stuck without the full sequence. |
| 3 | **Geotag by polling.** A 1 s loop fans a location to every camera; the Sony driver reads `DD30` and `DD31` before each write. | Enable the location link once at session start, push on an interval (5 s default) or on real movement, re-check enable flags only when `DD01` notifies a change. | Three GATT round trips per second for data the camera samples every few seconds wastes battery on both ends. |
| 4 | **Sony timezone faked.** Always the 95-byte packet with the "timezone present" flag, offset 0, and never reads `DD21`. | Read `DD21`; send the 91-byte form when the camera has no timezone support, otherwise the 95-byte form with the real standard offset and DST. | Offset 0 sets the wrong zone on cameras with auto area adjustment and may be rejected by firmware expecting 91 bytes. |
| 5 | **Camera clock never synced.** Only Nikon's time characteristic is defined, and it is unused; furble has no Fujifilm time packet and no Sony `DD32`/`DD33` handling (those come from GeoShutter and SonyGpsApp). | `syncClock()` once per session where the protocol has a time write: Fujifilm time packet (on request), Nikon time characteristic, Ricoh date/time, Sony via the location packet's timezone fields and the auto-time flag. | EXIF time and geotag time must agree; camera clocks drift. |
| 6 | **All-or-nothing multi-camera group.** One camera dropping sends the whole group back to connecting; commands are dropped meanwhile. | One camera at a time. No group state to get wrong. | Simpler pairing, unambiguous acknowledgement, fits the watch's two-connections-per-app limit. |
| 7 | **Reconnect by polling.** Two 30 s attempts, or an endless loop of 5 s attempts. | [Reconnect policy](#reconnect-policy): OS pending connect with auto-reconnect; app-level backoff only for registration failures. | Polling is the only tool NimBLE offers. Core Bluetooth already does this better and cheaper. |
| 8 | **Cargo-culted Fujifilm subscriptions.** The secure driver subscribes to 12 characteristics, most labelled "unknown" (two of them absent on the X100VI), and reads NOT1 `02 00` as "configured", a value current bodies do not send. | Subscribe to the minimum (NOT1, geotag request, sync interval, plus the state notifications in `4C0020FE`), treat NOT1 `01 00` as the camera's time request and answer it with the time packet (once its UUIDs are known; [Phase 5 doc](10-15-26_phase-5-other-brands-05.md#decisions-and-defaults)), never block on `02 00`, and keep an opt-in "full emulation" mode that subscribes to everything for bodies that misbehave. | Fewer failure points, and the state notifications are the only plausible place a shooting status could appear. |
| 9 | **Blocking work in callbacks.** Canon Smart writes from inside an indication callback and busy-waits up to 60 s for the user; progress bars are incremented artificially. | Every step is an awaited, cancellable task; progress comes from completed steps. | Required by Swift concurrency, and it makes "Cancel" actually cancel. |
| 10 | **Fix gated only on validity and age.** A 200 m urban fix is sent like a 3 m one. | Add a horizontal-accuracy threshold (50 m default) and never replace a recent good fix with a much worse one. Altitude stays mean-sea-level, as furble's GGA altitude already is. | EXIF consumers show the accuracy as truth. |
| 11 | **Small hazards.** `mktime` on a UTC tuple (works only because the ESP32 zone is UTC); Sony lat/lon cast through `uint32_t` (undefined for negative values, so southern/western fixes are not guaranteed); Ricoh auto-confirms numeric comparison and injects a fixed passkey; records keyed by MAC; Ricoh "location control" written to a characteristic another source identifies as the WLAN security type. | Use the fix's epoch timestamp directly; encode Int32 two's complement big-endian; let the system pairing dialogs run; key records by a stable ID with the peripheral identifier stored separately; use the documented GEO Tag characteristic. | Correctness, and the OS does not allow the shortcuts anyway. |
| 12 | **No automated tests.** CI builds the firmware; protocol regressions are found by users. | Transcript-replay tests for every driver with golden vectors taken from independent projects, property tests for every packet encoder, a fake camera for UI, `BLEKit` over CoreBluetoothMock in the simulator. | A phone app ships to many more bodies than an ESP32 remote; regressions must be caught before release. |

### Acknowledgement per brand

"Ack" means the camera tells us a focus or exposure actually happened. This is what each protocol offers, what xGRC subscribes to, and the fallback where nothing exists.

| Brand / mode | Focus ack | Shutter ack | Location ack | Source | Fallback when absent |
|---|:---:|:---:|:---:|---|---|
| Sony | ✅ `02 3F 20` / `02 3F 00` (only if the camera's shutter button runs AF; back-button-focus setups give none) | ✅ `02 A0 20` active, `02 A0 00` ready; `02 D5 xx` recording | ⚠ `DD01` is advisory (last byte 1 = on, 0 = off), absent on legacy firmware; on legacy bodies `DD11` writes succeed with Location Info. Link off and no EXIF is written, so the advertisement's location-enabled bit is checked before starting | `FF02` notify, documented by freemote and confirmed by alpharemote, GeoShutter and CameraSync; furble neither subscribes to nor decodes it | n/a |
| Ricoh | ✅ AF status notify `CDFC734E-EA21-427D-A69F-C1A0F7F1E9A3` (running, in focus) | ✅ capture status notify `B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA` (capturing, countdown, still, movie…), shot count | ✅ GEO Tag `A36AFDCF-6B67-4046-9BE7-28FB67DBC071` read/notify (0/1) | dm-zharov API doc; CameraSync (GR IIIx); furble subscribes but only logs | n/a |
| Fujifilm | ✖ unknown | ⚠ **research, probably absent**: the shutter service is write-only in Fujifilm's firmware GATT tables, and every notifying characteristic in `4E941240` is a setting; the only candidates are the state notifications in `4C0020FE` (TRANSFER_STATE may change per new image when auto-transfer is on, CAMERA_VITAL_STATE) | ✅ camera requests location (`01 00`) and stops asking when sync is off; NOT1 `01 00` = time request | Phase 6 (or a Phase 7 tester) captures the official app during shooting; the expected outcome is *assumed* | Timed press (hold 100 ms by default, configurable) reported as *assumed* |
| Canon Smartphone mode | ✖ not exposed | ⚠ **research**: CanonBLEIntervalometer subscribes to `00030031-…` "trigger state notifications" after writing `00 01`/`00 02`; xGRC subscribes in Phase 5 and decodes it from a Phase 6 capture | ✅ `00040003-…` indication `0x02` = enabled, `0x03` = request | Phase 6 | Timed press, *assumed* |
| Canon Remote (BR-E1) | ✖ | ✖ one-way protocol by design | n/a (no GPS) | BR-E1 has no return channel | Timed press, *assumed* |
| Nikon Remote (ML-L7) | ✖ | ⚠ indications arrive on `00002084-…`; furble logs them undecoded | n/a (no GPS) | Phase 6 decodes them | Timed press, *assumed* |
| Nikon Smart | ✖ unknown | ✖ unknown | ⚠ furble defines an unused constant `GEO = 00 01` with no characteristic attached; meaning unknown | post-1.0 capture | Timed press, *assumed* |

Rules that follow from the table:

- `DriverCapabilities` must declare `ackFocus` / `ackShutter` / `ackLocation` truthfully; the UI, the haptics and the intervalometer read them. A driver that claims an ack it cannot deliver fails its transcript tests.
- The shot counter shows two numbers wherever they can differ: *confirmed* and *sent*.
- Every "research" cell above is a phase exit criterion: the brand's driver is not called done until the ack source is either implemented or documented as absent after a capture of the official app.
- As built in Phase 5, only Sony claims acks. Ricoh's capture and AF status, Canon's `00030031` and Nikon's `2084` are subscribed and logged into the transcript, and those drivers report *assumed* until a Phase 6 capture decodes them ([Phase 5 doc](10-15-26_phase-5-other-brands-05.md#decisions-and-defaults), decisions 2 and 4).

---

## Apple platform constraints that shape the design

These are documented behaviours (Apple documentation unless stated); each has a mitigation in the architecture.

| Constraint | Effect | Mitigation |
|---|---|---|
| Core Bluetooth has **no API to initiate bonding**; pairing starts when the accessory rejects a request with *Insufficient Authentication* or sends a security request, and the system shows the dialog. | Driver `pair()` must deliberately touch a protected characteristic early (Sony `FF01`/`EE01`, Fuji status read, Canon ID write) so the prompt appears while the camera's pairing window is open; a camera that merely disconnects raises no dialog. | Drivers declare a `bondTrigger` step; UI tells the user to confirm the code on the camera; Phase 6 records which happens. |
| The OS **caches the GATT database** per peripheral; toggling Bluetooth does not clear it for a bonded device. Peripherals that implement Service Changed trigger `peripheral(_:didModifyServices:)`. | Missing characteristic after a camera firmware update. | Handle `didModifyServices` by rediscovering; if a characteristic is still missing, ask the user to Forget the device in Settings › Bluetooth (or via AccessorySetupKit) and on the camera. |
| **`bluetooth-central` does not keep the app running.** It only wakes a suspended app briefly for each BLE event. A background scan matches only advertised service UUIDs and ignores scan options. | Timers (intervalometer, release countdown, keep-alive) stop when the app is suspended. Manufacturer-data-only advertisements are invisible to background scans. | Background execution on iPhone exists only while a geotag session (location) runs; remote-only use, the intervalometer and the countdown need the foreground or a running geotag session on a brand with background shooting, and the UI says so. Saved cameras reconnect via pending `connect()` with auto-reconnect, never by background scanning. |
| **Location updates can auto-pause.** `CLLocationUpdate.liveUpdates()` and the default `pausesLocationUpdatesAutomatically = true` suspend updates, and then the app, when the device is stationary. | A tripod or still photographer loses the background process, the keep-alive and the countdown. | `startUpdatingLocation()` with `pausesLocationUpdatesAutomatically = false`; a 30-minute stationary run is part of the Phase 6 device test pass. |
| **State preservation & restoration** relaunches the app for a pending connection after the system terminated it. Not after a user force-quit or a Bluetooth power toggle; after a reboot only once the device is unlocked. Scene-based apps receive no launch options, so the restore identifier must be passed on every launch. Core Location likewise relaunches an app after system termination while a background activity session is outstanding, not after a user quit, and the session must be re-created immediately at launch. | Camera power-cycled while the app was system-terminated → we still reconnect; sessions survive crashes. | The central is created in the app delegate's launch method with a fixed restore identifier; `willRestoreState` restores pending peripherals; `LocationSource` re-creates the session at launch when a session record is open; onboarding hint not to swipe the app away during a session. |
| **Live Activities**: requested from the foreground (or by a `LiveActivityIntent`); static + dynamic content ≤ 4 KB combined; Lock Screen and expanded layouts truncated above 160 pt; the system throttles updates; the activity ends at 8 h (then up to 4 h stale on the Lock Screen). | The Island is a view of state, never what keeps the process alive. | Updates on state change and ≤ 1 per 10 s, `staleDate` set, countdown and age rendered by the system; re-request after 8 h; alerts only on countdown release and failures. |
| **Location in background** on iPhone needs the `location` background mode plus `allowsBackgroundLocationUpdates`, with `CLBackgroundActivitySession` (iOS 17+) for the indicator under When-In-Use. Using it for anything but location is an App Review 2.5.4 risk. | Required for geotag sessions; must not be started just to keep timers alive. | Only while geotagging; *While Using* permission only; review notes explain the purpose. |
| **Haptics are foreground-only.** On iPhone they need the foreground; on the watch `WKInterfaceDevice.play(_:)` has no effect while the app is background **or inactive** (wrist down, Always On dimmed), the only exception being an active workout session (excluded by decision 6). | The "vibrate once on release" promise can only be kept while the app is active on screen. | iPhone: in the background the confirmation is a Live Activity alert. Watch: the release haptic plays while active; a countdown that ends wrist-down shows the result on the next raise and in the Smart Stack tile, with a local notification as the fallback alert. |
| **watchOS runtime without HealthKit.** Core Bluetooth works while the app runs. With `bluetooth-central` in the watch app's `UIBackgroundModes` (edited by hand in the watch Info.plist), the system **keeps the connection when the app stops running** and wakes the app briefly for characteristic changes and disconnects (watchOS 9+, Apple Watch Series 6 or later; Series 4/5/SE 1st gen lose the link on leaving the app); the wake-ups are budgeted per rolling 24 h (5 on watchOS 9, shared with background scan grants), reset by user interaction, with `CBError.Code.leGattNearBackgroundNotificationLimit` / `.leGattExceededBackgroundNotificationLimit` delivered in the characteristic-update callback's error, after which the link is no longer kept. Each wake is a very short window, too short for a brand handshake. Long-running background session available to us: a continuous background location session (`location` mode, `allowsBackgroundLocationUpdates`, `CLBackgroundActivitySession` on watchOS 10+), which relaunches the app after a crash or system termination; Apple also documents that the watch shows the app on wrist raise while a background session runs. Extended runtime sessions are reserved for specific use types and do not fit. Limits: **two Bluetooth connections per app** (WWDC22); connection interval ≥ 30 ms in multiples of 30 ms (ADG R31). There is no API to extend frontmost time since watchOS 7; the user's per-app *Return to Clock* setting (default 2 minutes, up to 1 hour) decides it. After repeated supervision-timeout disconnects watchOS raises the RSSI it is willing to reconnect at for hours; only a Bluetooth toggle clears it, and Apple engineers recommend rescanning over auto-reconnect on the watch. | Remote-only shooting needs the app on screen; the link survives leaving the app but with few wake-ups; geotag sessions run in the background; a camera at the edge of range can lock the watch out. | *Return to Clock › After 1 Hour* guidance in onboarding, keep the Shutter page up; `bluetooth-central` mode so the link is kept between visits; `CLBackgroundActivitySession` for geotag sessions; brand handshakes only while running; foreground rescan on disconnect plus the reduced-range banner; Phase 6 measures link lifetime, the current wake-up budget, and whether notifications under a location session count, on the real watch. |
| watchOS and iOS are **different Bluetooth devices**. | Camera must be paired twice; some cameras allow one remote or one location linker; both devices could compete for the camera. | Pairing UI explains this; auto-reconnect only inside an active session on that device; the Sony lock is released on session end; the *Busy* state covers the rest. |
| **Another app's workout session running at the same time** (Apple Workout, Strava, etc.). Core Location is a shared service: several apps receive fixes concurrently. Core Bluetooth is multiplexed by the system with a two-connection limit **per app**, so the workout app's sensors do not count against xGRC. What does change: with a workout running, raising the wrist returns to the **workout app**, not to xGRC. | No GPS or Bluetooth conflict expected. A remote-only xGRC session loses frontmost status to the workout app on wrist-raise, but the camera link is kept by the system; a geotag session keeps running in its background location session. | Phase 6 runs xGRC alongside an Apple Workout session with one LE heart-rate sensor connected and records link stability and which app wins the wrist raise. UI: when another session is frontmost, the Smart Stack tile and the app switcher are the way back to xGRC; onboarding says so. |
| **The maker's app on the same device shares the bond and the physical link.** Bonds are system-wide; if Creators' App or XApp paired this iPhone, xGRC inherits the bond without a pairing prompt, and the maker's app's background connection can hold the camera's lock. Removing the bond in Settings unpairs the maker's app too. | Confusing first pairing; Busy states caused by the maker's app; Forget has side effects. | Add-camera detects existing bonds/connections and skips pairing mode; Busy copy names the maker's app; the Forget sheet says what else it unpairs. |
| **Bluetooth IO capability is undocumented** on iOS and watchOS; a community capture suggests watchOS presents DisplayOnly. | Passkey entry (Ricoh) may be impossible on the watch; numeric comparison (Fujifilm secure) may degrade to Just Works and be rejected. | Phase 6 pairs on the real watch; "not supported on watch" is an allowed outcome recorded in the support matrix. |
| Core Bluetooth centrals **cannot choose key distribution or connection parameters**; furble tunes them. | Link interval is whatever the camera asks for within Apple's guidelines. | Nothing to tune; measure the interval in the spike. |
| **Core Bluetooth has no MTU request API.** `maximumWriteValueLength(for: .withResponse)` reports up to 512 because the OS silently uses long writes; the single-packet limit is the `.withoutResponse` value. | A 95-byte Sony packet may be split into prepare/execute writes the camera does not support. | Check the `.withoutResponse` length, log, and flag long writes in the transcript. |
| **Double Tap** is a watchOS 11+ SwiftUI shortcut (`handGestureShortcut(_:isEnabled:)`) that performs a button-like control's **primary action**, one per scene, firing while the control is anywhere in the frontmost scene (scrolling toward it one page at a time if off screen); hardware is Series 9 / Ultra 2 and newer. Allowed on Smart Stack widgets and Live Activities. | The gesture cannot be mapped to "the second tap"; it is the button's action. Not page-scoped by itself. Minimum watchOS is 10, so the modifier is wrapped in an availability check. | The shutter is a `Button` whose action is *Shoot*, with a primitive button style that implements single tap = focus and double tap = trigger; `isEnabled: selectedPage == .shutter`; the Smart Stack tile declares the shortcut only while a session runs. Tested on Series 9 and on an older watch to confirm graceful absence. |
| **Widget intents run in the widget extension** unless they are `LiveActivityIntent` (iOS/iPadOS only, not watchOS), `ForegroundContinuableIntent` (watchOS 9.4+), or declare `supportedModes` (iOS/watchOS 26+). `openAppWhenRun` is deprecated on watchOS 26 in favour of `supportedModes`. Interactive watch widgets are watchOS 11+. | A plain widget intent has no BLE link and cannot wake a suspended app through the App Group. | Watch tile and Shoot control use `openAppWhenRun` (the documented way to run an intent in the app; needs a device check that it does so from the watch widget extension); iPhone Live Activity and Control use `LiveActivityIntent`. No App Group forwarding. |
| **Action Button and Controls.** Apple Watch Ultra: only workout and dive apps can use the Action Button (xGRC is neither, decision 6), so it is not supported; watchOS 26 adds app-built watch controls for Control Center and the Smart Stack. iPhone controls appear on the watch and run on the iPhone; controls whose action foregrounds the iPhone app are hidden on the watch. The iPhone's Live Activity appears in the watch Smart Stack (watchOS 11+), including Double Tap and alerts. | Two xGRC tiles can appear on the wrist. | watchOS 26+ watch control (no Action Button); iPhone control and Live Activity labelled "iPhone"; supplemental small activity family without a shutter button. |
| An **independent watchOS app** needs its own `NSBluetoothAlwaysUsageDescription` (required on watchOS 6+) and location usage strings and permission prompts, and the target is marked `WKRunsIndependentlyOfCompanionApp` (a "watch-only" app would mean no iOS app at all, which is not this product). | Onboarding and every permission prompt must be designed for the wrist; nothing can be deferred to the phone. | Watch target is created as an independent app from day one (Phase 1); all permission flows are tested with the iPhone app not installed and the phone's Bluetooth off or out of range. |
| App Store review requires usage strings and a justification for background modes; reviewers have no camera; store copy naming camera brands is a review risk; every executable needs a privacy manifest. | — | Strings, "compatible with" phrasing, a demo video and the review notes (no Demo camera: removed 2026-10-16) are Phase 7 deliverables (see the [phased plan](10-14-26_phased-plan-04.md)). |

---

## Budgets

Measured in the Phase 6 device test pass and recorded in `docs/support/`.

| Budget | Target |
|---|---|
| Touch-down → first ATT write on air | ≤ 30 ms on iPhone, ≤ 50 ms on watch |
| Second tap → full-press write on air | ≤ 1 connection interval |
| Shutter ack → haptic | ≤ 50 ms |
| Sony full sequence (4 writes with response) at a 30 ms interval | ≤ 250 ms excluding the focus wait |
| Live Activity alerts | Only on countdown release and failures; never per intervalometer frame |
| Foreground scan | Stops after 30 s or on leaving Add camera |
| Geotag battery cost | iPhone ≤ 5 %/h; watch ≤ 15 %/h while geotagging, ≤ 3 %/h remote-idle on screen |
| Watch wake-up budget | Zero budget wakes consumed by normal geotag or remote use (measured in Phase 6) |

---

## Testing strategy

- **Transcript tests.** Every driver ships with recorded GATT transcripts in schema v1 (`Fixtures/<brand>/<model>-<scenario>.jsonl`). A `ReplayTransport` feeds them to the driver; tests assert exact byte sequences and state transitions. Golden vectors come from independent projects' outputs (SonyGpsApp, sony-geotag, camera-gps-link, GeoShutter, CameraSync, dm-zharov), not from these docs, so the encoders are not checked against their own specification; real captures replace them as hardware arrives.
- **Property tests** for packet encoders (lat/lon ×10⁷ rounding and truncation, negative values, Nikon DMS conversion, Sony 91/95 selection and offsets, big/little endian).
- **Sequencer tests** for every row of the gesture table and the intervalometer rules, against `FakeCamera` with configurable ack latency and fault injection, on an injected test clock.
- **`BLEKit` tests** in the simulator over CoreBluetoothMock (restoration, error mapping, queueing, cancellation rule, notification-vs-read disambiguation). Not written yet; Phase 1 tests drivers and the sequencer over `FakeCamera`.
- **Running the tests.** `cd Packages/xGRCCore && swift test` runs the driver, sequencer, geotag and session tests (swift-testing) on a Mac or on Linux; `DesignKit` and the Core Bluetooth, Core Location and Keychain code are compiled only on Apple platforms.
- **The real camera is the test rig.** Every platform question (link lifetime, wake-up budget, pairing dialog, haptics, Double Tap) is answered by installing the app on the real watch and reading the transcript it logs. A hardware simulator is not planned; if one is ever wanted, a Mac `CBPeripheralManager` can emulate only service-UUID brands (Canon, Ricoh) because it cannot set manufacturer data, and an ESP32 would be needed for Sony, Fujifilm and Nikon.
- **Support records** in `docs/support/`: one file per body with transcripts, firmware version, pairing dialog type, negotiated interval, Sony remote/geotag coexistence, and EXIF proof. Bodies the developer does not own are covered by TestFlight testers' reports (transcripts cannot be exported).
- **Battery & runtime** noted in the Phase 6 device test pass against the Budgets table: watch battery percentage before and after a timed walk is enough.

---

## Repository layout

Created in Phase 1, except the targets marked with their phase. The Xcode project is generated from `project.yml` with XcodeGen and is not committed.

```
xGRC/
├── README.md                      ← overview, build quick-start, links into Dev_Doc
├── LICENSE                        ← GNU General Public License v3.0
├── privacy-policy.md             ← privacy policy (hosted at xdqin.com/xGRC/privacy-policy)
├── user-agreement.md             ← user agreement (hosted at xdqin.com/xGRC/user-agreement)
├── Dev_Doc/                       ← developer docs, named MM-DD-YY_what-was-done-NN.md (see README § Developer docs)
│   ├── 10-14-26_product-spec-01.md            product definition, scope, features, UI
│   ├── 10-14-26_architecture-02.md            this document
│   ├── 10-14-26_ble-protocol-reference-03.md  per-brand BLE protocols and sources
│   ├── 10-14-26_phased-plan-04.md             phased plan, work items, exit criteria
│   └── 10-15-26_phase-N-…-0N.md               what each build phase built, its device tests
├── project.yml                    ← XcodeGen spec (xcodegen generate → xGRC.xcodeproj)
├── Apps/
│   ├── xGRC-iOS/                  iOS + iPadOS app: Cameras, Add camera, Session, Geotagging, Settings, LiveActivityController,
│   │                              Assets.xcassets (AppIcon with dark and tinted variants)
│   ├── xGRC-watchOS/              independent watchOS app target: Cameras, Add camera, Pairing, Shutter, Geotag, Settings,
│   │                              Assets.xcassets (AppIcon)
│   ├── xGRC-Widgets-iOS/          Live Activity and Dynamic Island, the iOS 18 Shoot control
│   ├── xGRC-Widgets-watchOS/      Smart Stack tile and the watchOS 26 Shoot control
│   └── Shared/
│       ├── App/                   AppModel, ShutterButton, App Shortcuts, setting wording (both apps)
│       ├── Intents/               Shoot, Focus, Start/Stop geotagging (both apps and both widgets)
│       └── LiveActivity/          SessionActivityAttributes, ShootLiveActivityIntent (iOS app and widget)
├── Design/
│   └── AppIcon/                   app icon (Signal Lens with the amber location pin): SVG sources and notes
├── Packages/
│   └── xGRCCore/
│       ├── Sources/
│       │   ├── DesignKit/         Tally design tokens: palette, type, spacing, haptics, shutter and link-state appearance
│       │   ├── BLEKit/            GATT types, GATTTransport, BluetoothCentral, transcript, RecordingTransport
│       │   │   └── CoreBluetooth/ CoreBluetoothCentral, CoreBluetoothTransport (Apple platforms only)
│       │   ├── CameraKit/
│       │   │   ├── Core/          CameraDriver, ShotScript, ShotResult, DriverRegistry, GeoFix and location-link types,
│       │   │   │                  DriverLink (shared transport plumbing for the Phase 5 drivers)
│       │   │   └── Drivers/       Sony, Fujifilm (secure and legacy), Canon{Remote,Smart}, NikonRemote, Ricoh;
│       │   │                      FakeCamera/DemoCentral; Simulated/ (SimulatedPeripheral and each brand's body)
│       │   ├── LocationKit/       LocationSource, FixFilter, SimulatedLocationSource
│       │   │   └── CoreLocation/  CoreLocationSource with CLBackgroundActivitySession (Apple platforms only)
│       │   ├── SessionKit/        ShotSequencer, Intervalometer, GeoTagStreamer, CameraSession, SessionCoordinator,
│       │   │                      AutoDisconnect, ActivityPlanner
│       │   ├── SharedState/       TileState and ActivityState: what the widgets read (no BLEKit)
│       │   └── Persistence/       JSON stores, Keychain secrets, identities
│       └── Tests/                 transcript fixtures (schema v1) + unit tests
├── Tools/
│   └── Transcript/                PacketLogger/btsnoop → transcript converter, redactor (Phase 5)
└── docs/
    ├── protocols/                 one file per brand (generated from the protocol reference's tables, which stay canonical)
    └── support/                   per-body verification records and captures
```

---

## Open questions & risks

1. **watchOS BLE lifetime without a workout.** The single most important unknown. Apple documents that the system keeps the link after the app leaves (watchOS 9+) and that a background location session keeps the process running, but the real wake-up budget on current watchOS, whether notifications under a location session count against it, and link stability inside a location session are unmeasured. Phase 6 measures all three on the real watch. If the location session is not enough, watch geotag ships as beta.
2. **Watch pairing IO capability.** If the watch presents DisplayOnly, Fujifilm secure and Ricoh cannot pair on the wrist. Phase 6 decides; "not supported on watch" is an allowed outcome.
3. **Nikon SnapBridge mode.** Two implementations agree it needs a Classic bond on a separate address, and iOS SnapBridge appears to use the MFi accessory picker. A post-1.0 capture confirms; the likely outcome is "permanently out of scope".
4. **Canon Smartphone-mode details.** Two sources disagree on the `00030010` mode byte, the platform byte for iOS is untested, and the `00030031` trigger state is undecoded. Phase 5 builds both options; Phase 6 settles them on a body.
5. **Sony `EE01` registration** is written once on first pairing; whether it is also required for location link on bodies paired via AccessorySetupKit is unknown. Checked when a Sony body is on hand (Phase 6).
6. **Fujifilm shutter ack** is probably absent; a Phase 6 or tester capture settles it.
7. **Camera-side limits and cross-device competition** when a user pairs phone, iPad and watch: Sony one remote and one location linker; Fujifilm 7; Nikon 5 smart / 1 remote; Canon one function at a time. The Busy state, the Sony lock release on session end and session-scoped auto-reconnect are the mitigations.
8. **Live Activity throttling** could hide state changes; the Island is informational, never the only path to control.
9. **App Store review** of the background modes and of an independent watch app. Justification in review notes: BLE central is the product; location is sent to the connected camera and the indicator shows while it runs; no HealthKit, no workout, no analytics; a demo video for reviewers.
10. **Keychain persistence across reinstall** is undocumented; a lost `ClientIdentity` means re-pairing Canon Smart and Nikon bodies. The Forget-camera checklist covers it.
11. **Sony keep-alive trade-off.** Off by default costs the first ~10 s of shots after the camera wakes; on keeps the camera's screen on. Phase 6 measures both on one body.
