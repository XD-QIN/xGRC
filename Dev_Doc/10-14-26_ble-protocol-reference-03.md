# xGRC — Bluetooth protocol reference

The per-brand BLE protocols the drivers implement, and the sources they were checked against. The [product spec](10-14-26_product-spec-01.md) says what each brand supports; the [architecture doc](10-14-26_architecture-02.md) says how the drivers fit the app.

## Bluetooth protocol reference

Everything below was cross-checked between the furble source tree (`main` at commit `0cac22a`, October 2026; both `lib/furble` drivers and the `src/` application layer, re-verified byte-for-byte in review) and independent public sources listed in [References](#references). Confidence per brand is in the [support matrix](10-14-26_product-spec-01.md#camera-support-matrix); where sources disagree it is called out. **All UUIDs are 128-bit unless written as 16-bit.** Byte order and write type are stated per packet.

Common to all brands: the app is the GATT **central**; the camera **advertises** only while in its pairing menu (first time) or, once paired, briefly after power-on and whenever its "Bluetooth function" is on. After bonding, the OS re-encrypts automatically on reconnect.

### Sony (α / ZV / RX / FX bodies with "Bluetooth Rmt Ctrl")

**Advertisement** — manufacturer data, company ID `0x012D` (little-endian in the AD structure), layout:

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | Company ID `0x012D` |
| 2 | 2 | Device type `0x0003` = camera |
| 4 | 1 | Protocol version: `0x64` on older firmware, `0x65` on α7 III firmware ≥ 3.02 and 2023+ bodies. Independent tools gate the lock/enable writes on this byte "≥ 65", which is a decimal/hex confusion (both values exceed 65); xGRC only logs the byte and gates on **finding `DD30`/`DD31` in service discovery** |
| 5 | 1 | unused |
| 6 | 2 | Model code (used to key the pre-α7 IV exclusivity rule and the pairing instructions) |
| 8 | 1 | Tag `0x22` |
| 9 | 1 | **Mode flags**: bit7 pairing supported, bit6 pairing enabled, bit5 location supported, bit4 location enabled; bits 3–0 are disputed (furble reads bit1 as "remote enabled"; alpharemote observed its α6400 flip `0x04` instead and deliberately does not filter on it) |
| 10 | 1 | `0x00` |
| 11 | 1 | Tag `0x21` |
| 12 | 1 | Mode 21 flags |

freemote's observation "`22 EF 00` = open for pairing, `22 AF 00` = not pairing" matches bits 7 and 6. xGRC shows a camera as **pairable when bits 7 and 6 are set**, never filters on the low bits (a geotag-only user on a pre-α7 IV body has *Bluetooth Rmt Ctrl* Off on purpose), takes remote availability from `CC09` TLV tag `0x0003` or from the `FF01` write result (`0x90` ⇒ off), and logs byte 9 for the support table. Sony identifies itself by manufacturer data only, so this classification runs on foreground scans; background reconnection uses the pending connect.

**Services**

| Service | Characteristics | Purpose |
|---|---|---|
| `8000CC00-CC00-FFFF-FFFF-FFFFFFFFFFFF` | `CC02` write: auto-power-off avoidance `03 08 10 00` every 9 s (SonyGpsApp, copied from the Sony app's "APO avoidance" state); keeps the camera's screen on, so off by default (see Geotag defaults). `CC09` read: TLV camera info (tag `0x0003` = remote control available). `CC0F` card status, `CC10` battery (read/notify), decoded into `cardStatus` / `battery` events | Camera status |
| `8000FF00-FF00-FFFF-FFFF-FFFFFFFFFFFF` | `FF01` write with response (commands; error `0x90` = *Bluetooth Rmt Ctrl* Off), `FF02` notify (status) | Remote control |
| `8000DD00-DD00-FFFF-FFFF-FFFFFFFFFFFF` | `DD01` notify (advisory), `DD11` write (location packet), `DD21` read (features), `DD30` write (lock) and `DD31` write (enable) on newer firmware only, `DD32`/`DD33` read-write (auto time / auto area) | Location link |
| `8000EE00-EE00-FFFF-FFFF-FFFFFFFFFFFF` | `EE01` write with response | App-level pairing registration: `06 08 01 00 00 00 00`, found in the Creators' App iOS binary and accepted by an α7C II. xGRC writes it **exactly once, on the first connection, only while advertisement bit 6 (pairing) is set**, never on reconnects; written outside pairing mode it makes the camera disconnect. |

**Pairing** — the camera requires an encrypted, bonded link. In pairing mode the camera answers the first protected access (`FF01`, or `EE01`) with *Insufficient Authentication* or a security request, which raises the system pairing dialog; outside pairing mode it simply disconnects (the Phase 6 device test pass records which happens for each body tested). The camera must be in *Bluetooth → Pairing*. Menu placement differs by generation (2020–2021 bodies: *Network → Transfer/Remote → Bluetooth Rmt Ctrl*; 2022+ bodies: *Network → Bluetooth → Bluetooth Rmt Ctrl*, On by default), so the Add-camera instructions are keyed by the model code in the advertisement. Only one Bluetooth remote can be connected to the camera at a time. On iOS 18+ the AccessorySetupKit picker can do the bond (alpha-gps does this and then reconnects even after the user swipes the app away).

**Remote vs location link exclusivity.** Sony's help guides for bodies released before the α7 IV (α7 III, α7R III, α6400, ZV-E10, α1 and their generation) state that location-information linkage cannot be used while *Bluetooth Rmt Ctrl* is On. From the α7 IV on (α7 IV, α7C II, α6700, ZV-E1, ZV-1 II, α1 II…) the guides list only power saving as blocked, and GeoShutter confirms both work together on an α1 II. The camera never enters power save while *Bluetooth Rmt Ctrl* is On. xGRC keys the Remote-or-Geotag choice on the model code and records the real behaviour per body in the support table.

**Remote commands** (write with response to `FF01`, 2 bytes: length `0x01` then code; furble writes the same as a little-endian `UInt16`):

| Bytes | Meaning |
|---|---|
| `01 07` | Shutter half-press **down** (focus) |
| `01 06` | Shutter half-press **up** |
| `01 09` | Shutter full-press **down** |
| `01 08` | Shutter full-press **up** |
| `01 0F` / `01 0E` | Record down / up |
| `01 15` / `01 14` | AF-ON down / up |
| `01 21` / `01 20` | C1 down / up |
| `02 45 xx` / `02 44 xx` | Zoom tele press (step `0x10`–`0x8F`) / release (`0x00`–`0x0F`) |
| `02 47 xx` / `02 46 xx` | Zoom wide press / release |
| `02 6B xx` / `02 6A xx` | Focus in press / release |
| `02 6D xx` / `02 6C xx` | Focus out press / release |

alpharemote (v1.4) sends zoom presses with step `0x10`–`0x7F`, focus presses with step `0x00`–`0x7F`, and every jog release with step `0x00`. On cancel it sends the release of every button and jog it knows, which suggests a release of a button that is not down is harmless. Its README notes the focus jog only works with the camera in MF and the lens switch on AF.

Always send buttons in down/up pairs. **Sequence:** one shot is `01 07` → (focus ack) → `01 09` → (shutter ack) → `01 08` → `01 06`: half-down, full-down, **full-up, half-up**. That order is used by alpharemote, by CameraSync's notes from the decompiled Creators' App and by GeoShutter, and it is what furble's shutter-lock path produces; freemote's README lists half-up before full-up and is the outlier. furble's plain shutter button sends only `01 09` / `01 08`. Validated on hardware in the first field test with a Sony body (the Phase 6 device test pass).

**Status notifications** (`FF02`): `02 3F 00` focus lost, `02 3F 20` focus acquired, `02 A0 00` shutter ready, `02 A0 20` shutter active, `02 D5 00` / `02 D5 20` recording stopped / started (documented by freemote, confirmed by alpharemote, GeoShutter and CameraSync). xGRC subscribes to `FF02` immediately after bonding and uses these as the acknowledgement for every shot; furble does not subscribe to it. The focus ack only appears if the camera's shutter button is set to start AF. xGRC decodes a notification by its code (byte 1: `3F` focus, `A0` shutter, `D5` recording) and the state bit `0x20` of byte 2, as alpharemote does, so other bits in byte 2 or a longer value still decode; anything else is logged as unknown. `02 A0 00` also arrives when an exposure ends, which alpharemote uses to wait for a long exposure to finish.

**Bulb** — with a Bluetooth remote, bulb is a **toggle**: Sony's help guides (α7R IV, α7 IV, α7CR, ZV-1, RX100 VII) say "you can start bulb shooting by pressing the shutter button on the remote commander. To stop bulb shooting, press the shutter button on the remote commander again", and Sony's RMT-P1BT announcement says it "eliminat[es] the need to press and hold the button throughout exposure time". alpharemote's bulb timer does exactly that: half-down, full-down, wait for `02 A0 20`, full-up, half-up, count down, then half-down, full-down, full-up, half-up. A held full press is therefore **not** a bulb: releasing it does not close the shutter. xGRC's Sony `latch` is `01 09` · shutter ack · `01 08` · `01 06` (after the usual half-press and focus wait), its `unlatch` is `01 07` · `01 09` · `01 08` · `01 06`, and the closing press is sent only when the opening press drew the shutter ack: sent to a closed shutter it would open a bulb nobody closes. In any mode other than BULB each press takes a normal photo, so a timed bulb there takes two.

**Service Changed** — newer bodies (alpharemote does not name them) send a Service Changed indication to a bonded central a few hundred milliseconds after connecting, which restarts discovery and breaks anything already in flight (alpharemote 0.16d–0.17). Core Bluetooth reports it as `peripheral(_:didModifyServices:)`; xGRC's session re-registers (rediscover, resubscribe `FF02`) on it.

**Location link** — sequence (merged from furble, SonyGpsApp, ILCE7M3ExternalGps, camera-gps-link, sony-geotag):

1. Check `maximumWriteValueLength(for: .withoutResponse) ≥ 95` (ATT MTU ≥ 98; SonyGpsApp requests MTU 158). If smaller, log it and fall back to a with-response long write, flagged in the transcript, because the camera may not support prepare/execute writes.
2. Subscribe `DD01` (advisory: `03 01 02 01`-style values with last byte 1 = sync on, 0 = off; GeoShutter also lists `03 01 03 01` as "transfer available").
3. Read `DD21` and log its length and bytes in the transcript. SonyGpsApp requires ≥ 5 bytes; sony-geotag accepts only 6 or 7 bytes; the α7C II returns `06 10 00 9C 02 00 00`. xGRC: byte 4 bit `0x02` set on a 6–7-byte value ⇒ the **95-byte** packet with timezone/DST; any other length ⇒ treat as an unknown profile and send the **91-byte** packet.
4. If `DD30`/`DD31` exist: write `0x01` to `DD30` (lock) then `0x01` to `DD31` (enable). furble reads both first and only writes if not already `0x01`. ATT error `0x9D` (157) = the camera's Location Info. Link is off, or the camera is switched off with *Cnct. while Power OFF* on; `0x9F` (159) = another device or app (Creators' App, or the user's other phone/watch) holds the lock. Older firmware has neither characteristic and accepts `DD11` directly, and on those bodies the write succeeds even when Location Info. Link is off (no EXIF results), so the advertisement's location-enabled bit is checked first.
5. Write the packet to `DD11` on the geotag interval; keep the link enabled for the whole session (a capture only geotags while the location window is active). On stop, write `0x00` to `DD31` then `DD30` where present.

**`DD11` packet** (big-endian, write with response):

| Offset | Size | Value |
|---|---|---|
| 0 | 2 | Payload length: `00 5D` (93) for 95-byte form, `00 59` (89) for 91-byte form |
| 2 | 3 | `08 02 FC` |
| 5 | 1 | `03` if timezone fields present, else `00` |
| 6 | 5 | `00 00 10 10 10` |
| 11 | 4 | Latitude × 10⁷, Int32 two's complement |
| 15 | 4 | Longitude × 10⁷, Int32 two's complement |
| 19 | 2 | UTC year |
| 21 | 5 | Month, day, hour, minute, second (UTC) |
| 26 | 65 | Zeros |
| 91 | 2 | Standard UTC offset in minutes, **excluding DST**, Int16 (95-byte form only) |
| 93 | 2 | DST savings currently in effect in minutes, else 0, Int16 (95-byte form only) |

furble always sends the 95-byte form with offset 0 and never reads `DD21`; the phone projects read `DD21` first. xGRC does the latter and fills the real standard offset and DST so the camera's "auto area adjustment" (`DD33`) works.

### Fujifilm (X and GFX)

**Advertisement** — company ID `0x04D8`, then a type byte:

- `0x02` + 4-byte **pairing token** (manufacturer data exactly 7 bytes) → *legacy* firmware. Advertises service `AF854C2E-B214-458E-97E2-912C4ECF2CB8` or `117C4142-EDD4-4C77-8696-DD18EEBB770A`.
- `0x01` + 5-byte **serial** (exactly 8 bytes) → *secure* firmware. First wave 22 July 2025 (X-T5 4.30, X100VI 1.30, X-T50, X-S20, X-M5, GFX100RF, X half; Fujifilm's notes say the pairing procedure changed, wireless security was enhanced, and the older iOS Camera Remote app no longer connects); X-H2 / X-H2S later in 2025; X-E5 and later bodies ship with it. **Detection is by the advertisement type byte, never by a model list.** Unregistered cameras advertise `A9D2B304-E8D6-4902-8336-352B772D7597`; an already-registered camera advertises `123D8F06-62A1-4935-9322-833C531EE225` plus its serial, from a **resolvable private address**. After bonding, Core Bluetooth resolves it with the camera's identity key, so the peripheral identifier stays stable; the serial match is the fallback. **Every new registration gives the camera a new identity address**, so if XApp (or another xGRC device) registers afterwards, the stored peripheral is invalid and the camera must be paired again in xGRC. The camera advertises only briefly after power-on (about 6–10 s) and stops about 30 s after losing a link.

**Services & characteristics** (confirmed by furble, GeoShutter's protocol doc tested on X100VI fw 1.32, and the firmware GATT tables extracted by fffw for X-T5 4.30 / X100VI 1.31 / X-S20 3.30):

| Purpose | Service | Characteristic |
|---|---|---|
| Legacy pairing | `91F1DE68-DFF6-466E-8B65-FF13B0F16FB8` | `ABA356EB-9633-4E60-B73F-F52516DBD671` write 4-byte token; `85B9163E-62D1-49FF-A6F5-054B4630D4A1` write client name |
| Secure pairing | `123D8F06-62A1-4935-9322-833C531EE225` | `F557D96B-8284-4667-8793-B971C1DECA2A` status: read 4 bytes, write back with byte 3 = `0x20`; `85B9163E-…` write client name (UTF-8) |
| State notifications | `4C0020FE-F3B6-40DE-ACC9-77D129067B14` | `A68E3F66-…` ind (AP state), `BD17BA04-…` ind (TRANSFER_STATE), `F9150137-5D40-4801-A8DC-F7FC5B01DA50` notify (**NOT1 = DATE_SYNC_STATE**: `01 00` = camera asks for the time; furble reads `02 00` as "configured" but the X100VI never sends it), `AD06C7B7-F41A-46F4-A29A-712055319122` notify (**geotag request `01 00`**), `049EC406-…` ind (legacy driver only), `E6692C5C-…` notify (CAMERA_VITAL_STATE) |
| Camera settings | `4E941240-D01D-46B9-A5EA-67636806830B` | `BF6DC9CF-…` camera name (read); `AAB609C4-94DD-4D89-BC60-665D5090B828` LOCATION_SYNC_SETTING (uint16); **`C95D91AE-B247-4D6D-8661-7DD5D6A0F85B` LOCATION_SYNC_CYCLE** (uint16 seconds: 10, 15, 20, 30, 60, 120, 240, 480; write + notify); other notifying characteristics here are settings (image transfer, resize, logging), not shooting status |
| Geotag packet | `3B46EC2B-48BA-41FD-B1B8-ED860B60D22B` | `0F36EC14-29E5-411A-A1B6-64EE8383F090` write with response, 23 bytes |
| Time packet | `E872B11F-…` | `C52EDBCE-…` write 12 bytes (GeoShutter; not in furble; the camera applies it only after asking via NOT1 `01 00`, which it does on the first connection after power-on) |
| Shutter | `6514EB81-4E8F-458D-AA2A-E691336CDFAC` | `7FCF49C6-4FF0-4777-A03D-1A79166AF7A8` write with response; the whole service is write-only in the firmware tables, so no shutter ack lives here |
| Power | `804DAA8E-FFEB-4AB3-8E75-6EDD7303208D` | `7170FD5A-…` "connect while power off" (read/write uint16) |

**Pairing**

- *Secure:* connect → system bonding with **LE Secure Connections, numeric comparison**; the camera shows a 6-digit code that must be confirmed on the camera within 30 s → read status, write it back with byte 3 = `0x20` → write client name → subscribe to the notification set (NOT1 and the geotag-request notify are mandatory) → write sync interval → get shutter characteristic. GeoShutter warns that bonding **without** completing registration leaves the camera refusing connections for ~4½ minutes, which is why the AccessorySetupKit picker must not be used for Fujifilm (it bonds on its own connection and ends it). xGRC does not block on any NOT1 value. It does not answer NOT1 `01 00` yet: the time packet's full UUIDs are not known, so NOT1 values are only logged and the camera keeps its own clock ([Phase 5 doc](10-15-26_phase-5-other-brands-05.md#decisions-and-defaults), decision 1). GeoShutter completed this flow from an iPhone 15 Pro Max (Sept 2026) with the code confirmation taking about 8 s.
- *Legacy:* connect (furble never initiates encryption; the camera may still request it) → write the 4-byte token from the advertisement to the pairing characteristic → write client name → subscribe → write sync interval (10 s, where the camera has the characteristic) → get shutter characteristic. The token is reused on every reconnect.

**Shutter** — two consecutive writes with response to the shutter characteristic, each 2 bytes little-endian: `01 00` (command) then the parameter: `02 00` full press, `03 00` half press (focus), `00 00` release. Release ends both focus and shutter. A half-press focuses only if the camera's shutter button is set to start AF (furble discussion #99).

**Geotag** — the camera **pulls**: every *sync interval* seconds it sends `01 00` on the geotag-request characteristic; the app answers with one 23-byte little-endian packet:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | Latitude × 10⁷, Int32 |
| 4 | 4 | Longitude × 10⁷, Int32 |
| 8 | 4 | Altitude, whole metres, Int32 |
| 12 | 4 | Speed, m/s × 100, Int32 (furble sends 0) |
| 16 | 2 | UTC year |
| 18 | 5 | Month, day, hour, minute, second (UTC) |

Caveats, from Fujifilm's own Camera Remote / XApp help: location data not updated for more than 3 hours is no longer embedded; the official app does not transmit fixes older than 2 hours; the camera's location icon turns red after 30 minutes without an update (xGRC mirrors this in the Geotag page's "last push" colour); the camera stores up to 7 paired devices. GeoShutter adds the unverified report that the camera ignores a packet whose timestamp is not newer than the last one, so xGRC stamps answers with the send time and skips an answer that would not be newer; with *Location sync* off on the camera it never asks. The geotag packet does **not** set the camera clock; the separate time packet does. "Silent" connections (setup accepted, then nothing) occur; the planned watchdog in the reconnect policy is for them, and until it is built the general reconnect policy handles them. GeoShutter's Fujifilm geotag EXIF is verified on Android; EXIF from an iOS geotag is still to be confirmed, and the iPhone part of the device test pass (Phase 6) does that.

### Canon EOS / PowerShot

All Canon UUIDs share the base `xxxxxxxx-0000-1000-0000-D8492FFFA821`. Canon bodies hold **one** Bluetooth function at a time (Smartphone or Remote; one device).

**Mode A — "Remote" (the camera is told to pair a *wireless remote*; we emulate a BR-E1).** Verified by furble, canoremote, eos-remote-web, ESP32-Canon-BLE-Remote and Ian Douglas Scott's write-ups.

- Advertises service `00050000-…`.
- Connect → system bonding (Just Works) → write `0x03` + our device name to `00050002-…` (identification) → control characteristic `00050003-…`.
- Control byte = **mode | buttons**: modes `0x0C` immediate, `0x04` 2-s delay, `0x08` movie; buttons `0x80` shutter, `0x40` focus (half), `0x20` tele, `0x10` wide. Press shutter = write `0x8C`; focus = `0x4C`; release = `0x0C`. xGRC writes with response wherever the camera's characteristic allows it, so errors are reported, and without response (with readiness flow control) otherwise; furble writes with response ([Phase 5 doc](10-15-26_phase-5-other-brands-05.md#decisions-and-defaults), decision 6).
- **Camera-side requirement:** the camera only reacts when its drive mode is *Self-timer: 10 s/remote* or *2 s/remote*; movies additionally need *Shooting › Remote control: Enable*. Shown in the pairing steps and as a hint after the first assumed shot.
- No GPS in this mode (camera only takes location from a *smartphone* pairing; pairing a wireless remote stops smartphone location acquisition).

**Mode B — "Smartphone" (camera pairs us as Camera Connect).** Sources: furble and robot9706/CanonBLEIntervalometer (EOS M50); camera-gps (Android) follows furble.

- Advertises service `00010000-…`.
- Connect → system bonding (Just Works) → subscribe indications on `00010006-…` (pairing result: `0x02` accept, `0x03` reject, chosen by the user on the camera within ~60 s) → write `0x01`+name to `00010006-…` → write `0x03`+our 16-byte UUID, then `0x04`+name, then `0x05`+platform byte to `0001000A-…` (platform: `0x01` iOS, `0x02` Android, `0x03` remote controller per CanonBLEIntervalometer; furble sends `0x02`; xGRC tests `0x01` first) → wait for accept → write `0x01` to `0001000A-…` → write the mode byte to `00030010-…` (service `00030000-…`): furble writes `0x02` (its "shoot" value; `0x01` playback, `0x03` wake), CanonBLEIntervalometer writes `0x03` and describes the characteristic as configuring the trigger-state notifications. The driver writes `0x02` (the constant `Canon.shootMode`, not a setting); the device test pass (Phase 6) confirms it or switches the constant to `0x03`.
- Shutter: service `00030000-…`, characteristic `00030030-…`: `00 01` press, `00 02` release ("finish the trigger and get the result"). No separate half-press. **`00030031-…` notifies the trigger state** (CanonBLEIntervalometer); xGRC subscribes to it as the candidate shutter ack.
- Geotag: service `00040000-…`; subscribe indications on `00040003-…`. When the camera indicates `0x03` (request), write `0x01` to `00040002-…` to enable; `0x02` means enabled. Then write **20-byte** packets to `00040002-…` (little-endian floats, as furble's ESP32 does):

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | `0x04` |
| 1 | 1 | `'N'` / `'S'` |
| 2 | 4 | Latitude, Float32, absolute degrees |
| 6 | 1 | `'E'` / `'W'` |
| 7 | 4 | Longitude, Float32, absolute degrees |
| 11 | 1 | `'+'` / `'-'` |
| 12 | 4 | Elevation, Float32, metres |
| 16 | 4 | Unix time, UInt32 seconds |

Camera-side setting: *GPS device settings → Select GPS device → Smartphone*. Canon's manual notes direction (heading) is never acquired and acquisition stops when the camera powers off, Camera Connect quits, or a wireless remote is paired.

### Nikon

Service `0000DE00-3DD4-4255-8D62-6DC7B9BD5561`; characteristics share the same base. Company ID `0x0399`. furble never initiates encryption on Nikon in either mode. The camera connects to one device type at a time (remote *or* smart device) and to one remote only.

**Advertisement** — while in its pairing menu the camera advertises the service UUID with **no manufacturer data**. A previously paired camera advertises manufacturer data `99 03` + the 4-byte *device ID* we gave it during pairing + `00`; xGRC re-finds a saved Nikon by the resolved peripheral identifier first and by device ID on a foreground scan as fallback.

**Mode A — "Connection to remote" (ML-L7 emulation).** Source: furble (tested COOLPIX B600, Z6 III). Single-source.

- Subscribe indications on `00002084-…`; subscribe indications on the pairing characteristic `00002087-…`.
- Handshake on `00002087-…`, 17-byte messages: `stage(1) | timestamp(8) | id(8)` where `id = device(4) | nonce(4)`. We write the stage-1 message (timestamp `0x0000000000000001` big-endian, our random ID with the device ID's first byte forced to `0x01`); the camera indicates stage 2 (all-zero body); we write stage 3 (zeros); the camera indicates stage 4 carrying its 8-char serial. furble prepares a stage-5 message but never writes it; the link is then ready. 10 s timeout per camera response.
- Shutter: write 2 bytes to `00002083-…`: `02 02` press, `02 00` release (first byte is the control mode: `0x02` shutter, `0x03` video, `0x04` menu, `0x05` playback).
- **Bulb runs as Time** with a wireless remote on Nikon bodies: the first press/release opens the shutter and the next press/release closes it; a held press does not keep it open. The driver's `latch` and `unlatch` scripts are therefore the same press/release pair, and the UI says so.
- No focus control and no GPS in this mode.

**Mode B — SnapBridge "smart device".** Research item, likely out of scope.

- Pairing characteristic `00002000-…`, success notify `00002008-…` (`01 00`), client ID `00002002-…`, time `00002006-…` (10 bytes: year u16, month, day, hour, min, sec, DST offset, TZ hours, TZ minutes), **location `00002007-…`** (41 bytes).
- Handshake: same 17-byte stage messages, but stage 3's ID is a Blowfish-based hash of `salt[i] ‖ our timestamp ‖ camera timestamp` with key `FF FF AA 55 11 22 33 00` and one of 8 known salts (the camera's stage-2 ID tells us which salt). furble implements this, gets the `01 00` success notification, writes the client name, and then reports that the camera moves on to a Bluetooth Classic bond.
- hurui200320/nsg (Android app verified on Z7 II, Z50 II and Z8; ESP32 build that needs a chip with a Classic radio) documents the mechanism: after the BLE handshake the camera exposes a **separate Classic (BR/EDR) public address**, the phone must close its GATT connection, discover and bond that Classic address, and only then does the location characteristic accept writes. Its GPS payload uses degrees and decimal minutes, consistent with the packet layout above.
- Location packet (little-endian header `0x007F` = all-fields-valid flags; coordinates as degrees/minutes/hundredths/hundredths-of-hundredths; `'N'/'S'`, `'E'/'W'`; satellites; altitude sign `'P'`/`'M'` + UInt16 metres; UTC time + centiseconds; valid `0x01`; literal `WGS-84`; 10 bytes padding).
- **Why iOS SnapBridge works:** Nikon's manuals tell iOS users "if prompted to choose an accessory, tap the camera name", and users report a "Select an Accessory" sheet. That is the External Accessory (MFi) Bluetooth picker, which third-party apps can only use for MFi accessories they are entitled to. A separate Classic address also argues against cross-transport key derivation (which iOS supports since iOS 13, but which derives keys for the *same* device identity). The post-1.0 research item captures SnapBridge on iOS to confirm; if the EA picker is confirmed, this mode is marked permanently out of scope.

### Ricoh GR III / IIIx / IV

Sources: furble (GR IV only; its Ricoh GPS path is a logging stub), the community API doc dm-zharov/ricoh-gr-bluetooth-api (GR II/III/IIIx and Pentax; a specification, not an implementation), and CameraSync (Android implementation of GPS and clock on a GR IIIx, with notes from the decompiled GR WORLD app). Ricoh's own GR WORLD app (July 2025) provides location over Bluetooth to GR III bodies on firmware 2.00+.

| Service | Characteristic | Use |
|---|---|---|
| Camera information `9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1` | `35FE6272-6AA5-44D9-88E1-F09427F51A71` | Model number (read) |
| Camera `4B445988-CAA0-4DD3-941D-37B4F52ACA86` | `B58CE84C-0666-4DE9-BEC8-2D27B27B3211` power (0 off, 1 on, 2 sleep); `1452335A-EC7F-4877-B8AB-0F72E18BB295` operation mode; **`A36AFDCF-6B67-4046-9BE7-28FB67DBC071` GEO Tag** (read/write/notify, 0/1: the camera's *Store Location Info.* switch); date/time characteristic (write) | Status, geotag enable, clock |
| Shooting `9F00F387-8345-4BBC-8B92-B87B52E3091A` | **`559644B8-E0BC-4011-929B-5CF9199851E7` Operation Request** `[code, param]`: code 0 NOP / 1 start / 2 stop; param 0 no-AF / 1 AF / 2 green button. `B29E6DE3-1AEC-48C1-9D05-02CEA57CE664` Shooting flavour (0 immediate, 2 = 2-s timer). `B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA` capture status (notify). `CDFC734E-EA21-427D-A69F-C1A0F7F1E9A3` AF status (notify: running, in focus). `009A8E70-…` self-timer (write) | Shutter and acks |
| Bluetooth control `0F291746-0C80-4726-87A7-3C501FD3B4B6` | `FE3A32F8-A189-42DE-A391-BC81AE4DAA76` paired device name; BLE-enable-condition (Bluetooth on while the camera is off) | Pairing |
| GPS `84A0DD62-E8AA-4D0F-91DB-819B6724C69E` | **`28F59D60-8B8E-4FCD-A81F-61BDB46595A9` GPS information** write 32 bytes | Geotag |
| `F37F568F-9071-445D-A938-5441F2E82399` / `9111CDD0-9F01-45C4-A2D4-E09E8FB0424D` | furble calls this "location control" and writes `0x01` to enable geotagging; CameraSync's GR WORLD analysis identifies `9111CDD0` as the **WLAN security type** (0 WPA2, 1 WPA3, 2 transition) and `F37F568F` as a device-information bridge. **xGRC never writes it.** | — |

- Pairing: LE Secure Connections with **passkey / numeric comparison** displayed on the camera (furble advertises keyboard-display capability). Must be encrypted, authenticated and bonded or the camera rejects writes. Whether a watch can complete this depends on the IO capability it presents (measured in Phase 6).
- Shutter is a single operation: write flavour `0` then `[01, 01]` (start with AF). There is no half-press: `press(.focus)` is unsupported and AF runs inside the capture. The camera's 2-s timer flavour is exposed as `cameraSelfTimer`, outside the gesture model. Stop (`[02, xx]`) is used for movie / long exposures.
- Geotag enable: read GEO Tag; if `0`, show "Turn on Store Location Info. on the camera" and write `1` only after the user confirms; subscribe for changes.
- GPS packet, big-endian except year: latitude, longitude, altitude as Float64; year Int16 **little-endian**; month, day, hour, minute, second; last byte datum `0` = WGS-84 (furble puts centiseconds in that slot; the API doc says datum; CameraSync sends the documented form; xGRC sends `0`). Timestamp is the time of the fix, UTC. furble rate-limits to one write per 10 s or on movement ≥ 0.00001° / 1 m.

### Cross-brand behaviours xGRC must implement

| Behaviour | Brands |
|---|---|
| Camera pulls location on a timer; we answer | Fujifilm |
| We push location on a timer / movement | Sony, Canon Smart, Ricoh, Nikon Smart |
| Camera must be *enabled* for location before packets | Sony (`DD30`/`DD31` where present), Canon Smart (`00040002` ← `0x01`), Ricoh (GEO Tag, user-confirmed) |
| Camera uses a resolvable private address; rely on the resolved identifier, fall back to serial / ID match on a foreground scan | Fujifilm secure, Nikon |
| App-level identity we must persist | Fujifilm legacy (token), Fujifilm secure (serial), Nikon (device+nonce); Sony and Canon need only the bond; Canon Smart stores *our* UUID+name camera-side |
| Two-write command | Fujifilm shutter |
| Shutter and focus are separate buttons | Sony, Fujifilm, Canon Remote |
| Bulb as Time (press opens, next press closes) | Nikon Remote, Sony (bulb with a Bluetooth remote) |
| Camera acknowledges focus/shutter | Sony (`FF02`), Ricoh (AF status, capture status); Fujifilm (probably absent), Canon Smart (`00030031`) and Nikon Remote are research items; Canon Remote has none. See [Acknowledgement per brand](10-14-26_architecture-02.md#acknowledgement-per-brand) |
| Optional keep-alive during geotag sessions | Sony (`CC02`, 9 s, keeps the screen on; off by default) |
| Remote and geotag mutually exclusive per session | Sony pre-α7 IV bodies; Canon (one Bluetooth function at a time: Smartphone or Remote) |
| Camera-side mode that must be set for the shutter to work | Canon Remote (drive mode self-timer/remote; movies need Remote control: Enable) |

### Link security (what furble sets and what Apple platforms decide)

- furble's link security for every brand that initiates encryption is *bonding + MITM + LE Secure Connections*, with *display-yes/no* IO capability by default and *keyboard-display* for Ricoh; keys distributed are the encryption key and the identity key (IRK), and furble uses a resolvable private address. Exceptions: Fujifilm legacy and Nikon (both modes), which furble connects to **without** initiating encryption; the camera may still request it.
- On Apple platforms none of this is configurable, and Apple does not document the IO capability iOS or watchOS present. A community packet capture suggests watchOS presents *DisplayOnly*; Phase 6 finds out by pairing on the real watch (a sniffer capture is optional), because it decides whether Fujifilm secure (numeric comparison) and Ricoh (passkey) can pair on the watch at all.
- furble sets the connection interval to the stack defaults with slave latency 1 and a doubled supervision timeout to extend range. A Core Bluetooth central cannot set connection parameters; the camera requests them and the OS accepts within the Accessory Design Guidelines (R31 §58.6): minimum interval ≥ 15 ms in multiples of 15 ms on iPhone and ≥ 30 ms in multiples of 30 ms on Apple Watch, slave latency ≤ 30, supervision timeout 6–18 s; Apple recommends an interval of at least 150 ms for accessories that stay connected in the background. xGRC logs the negotiated interval from Phase 1 on and keeps its own notification and write rates low; on the watch the binding limit is the background event budget, not a rate cap.

---

## References

Sources for the product spec, the architecture doc and this reference.

Primary reference:
- gkoh/furble — https://github.com/gkoh/furble (Fujifilm, Canon, Nikon, Sony, Ricoh drivers; source read in full at commit `0cac22a` for this document)

Independent verification used in these docs:
- Sony remote: Staacks/alpharemote — https://github.com/Staacks/alpharemote (GPL-3.0; read at `4a950a8`, v1.4, for the [comparison](10-15-26_sony-alpharemote-review-06.md); protocol facts only, no code copied) ; rock3r/CameraSync (Sony and Ricoh notes from the decompiled Creators' App and GR WORLD) — https://github.com/rock3r/CameraSync ; coral/freemote — https://github.com/coral/freemote ; Greg Leeds — https://gregleeds.com/reverse-engineering-sony-camera-bluetooth ; Hypoxic — https://gethypoxic.com/blogs/technical/sony-camera-ble-control-protocol-di-remote-control
- Sony location link: narumiruna/camera-gps-link (iOS, α7C II EXIF confirmed, Creators' App iOS binary notes) — https://github.com/narumiruna/camera-gps-link ; Asdoos/SonyGpsApp — https://github.com/Asdoos/SonyGpsApp ; whc2001/ILCE7M3ExternalGps (PROTOCOL.md) — https://github.com/whc2001/ILCE7M3ExternalGps ; narumiruna/sony-geotag — https://github.com/narumiruna/sony-geotag ; steven801212/sony-alpha-esp32-gps — https://github.com/steven801212/sony-alpha-esp32-gps ; Saschl/alpha-gps (iOS, AccessorySetupKit; issues #95, #260) — https://github.com/Saschl/alpha-gps ; anoulis/sony_camera_bluetooth_external_gps — https://github.com/anoulis/sony_camera_bluetooth_external_gps
- Fujifilm: sarmadjari/GeoShutter `docs/fujifilm-protocol.md` — https://github.com/sarmadjari/GeoShutter ; tiredboffin/fffw (firmware GATT tables) — https://github.com/tiredboffin/fffw ; furble discussion #99 (shutter-button AF) — https://github.com/gkoh/furble/discussions/99 ; petabyt/fudge — https://github.com/petabyt/fudge ; hkr/fuji-cam-wifi-tool — https://github.com/hkr/fuji-cam-wifi-tool
- Canon: Ian Douglas Scott — https://iandouglasscott.com/2017/09/04/reverse-engineering-the-canon-t7i-s-bluetooth-work-in-progress/ and https://iandouglasscott.com/2018/07/04/canon-dslr-bluetooth-remote-protocol/ ; pklaus/canoremote — https://github.com/pklaus/canoremote ; RReverser/eos-remote-web — https://github.com/RReverser/eos-remote-web ; robot9706/CanonBLEIntervalometer — https://github.com/robot9706/CanonBLEIntervalometer ; asteppke/ESP32-Canon-BLE-Remote — https://github.com/asteppke/ESP32-Canon-BLE-Remote ; ArthurFDLR/BR-M5 — https://github.com/ArthurFDLR/BR-M5 ; mcfitz2/camera-gps — https://github.com/mcfitz2/camera-gps
- Ricoh: dm-zharov/ricoh-gr-bluetooth-api — https://github.com/dm-zharov/ricoh-gr-bluetooth-api ; rock3r/CameraSync (above); Ricoh GR WORLD announcement — https://news.ricoh-imaging.co.jp/rim_info2/2025/20250715_041137.html
- Nikon: hurui200320/nsg (`doc/nikon-z-gps.md`) — https://github.com/hurui200320/nsg ; Nikon SnapBridge help — https://nikonimglib.com/snbr/onlinehelp/en/bluetooth_pairing_4.html and https://nikonimglib.com/snbr/onlinehelp/en/02_connect_02.html ; Nikon 2016 SnapBridge release — https://www.nikon.com/company/news/2016/0106_snapbridge_04/ ; Z f manual, ML-L7 options — https://onlinemanual.nikonimglib.com/zf/en/nwm_wireless_remote_ml-l7_options_331.html ; Z50 mode dial (Bulb as Time with ML-L7) — https://onlinemanual.nikonimglib.com/z50/en/06_shooting_controls_01.html
- Sony bulb with the Bluetooth remote (toggle): α7 IV — https://helpguide.sony.net/ilc/2110/v1/en/contents/TP1000640135.html ; α7R IV — https://helpguide.sony.net/ilc/1930/v1/en/contents/TP0002711806.html ; α7CR — https://helpguide.sony.net/ilc/2370/v1/en/contents/0302C_bulb.html ; ZV-1 — https://helpguide.sony.net/dc/1910/v1/en/contents/TP0002869961.html ; RX100 VII — https://helpguide.sony.net/dsc/1920/v1/en/contents/TP0001140416.html ; RMT-P1BT announcement — https://www.sony.com.hk/press/pdf/20190404_2_e.pdf
- Camera makers' help (user-facing facts): Sony Bluetooth Rmt Ctrl and Location Information Linkage, older generation — https://helpguide.sony.net/ilc/2040/v1/en/contents/TP1000425296.html , https://helpguide.sony.net/ilc/2040/v1/en/contents/TP1000416843.html , https://helpguide.sony.net/ilc/1950/v1/en/contents/TP0002679686.html ; newer generation (power save only) — https://helpguide.sony.net/ilc/2110/v1/en/contents/TP1000656752.html , https://helpguide.sony.net/ilc/2320/v1/en/contents/0706_bluetooth_remote.html , https://helpguide.sony.net/ilc/2310/v1/en/contents/0706_bluetooth_remote.html ; Fujifilm location info (3 h / 2 h rules) — https://app.fujifilm-dsc.com/en/manual/camera_remote/usage/location_info/ ; Fujifilm paired devices (7) — https://app.fujifilm-dsc.com/en/manual/gfx100/connections/wireless/index.html ; Fujifilm X100VI firmware notes (22 July 2025 pairing change) — https://fujifilm-x.com/en-us/support/download/firmware/cameras/x100vi/ ; Canon EOS R8 GPS device settings — https://cam.start.canon/en/C013/manual/html/UG-07_Network_0150.html ; Canon remote control shooting (drive mode) — https://cam.start.canon/en/C010/manual/html/UG-04_AF-Drive_0120.html
- Prior art apps (App Store): sMoteWatch — https://apps.apple.com/app/id1669571304 ; WatchShutter Pro — https://apps.apple.com/it/app/watchshutter-pro/id6755309531 ; Shot Bridge — https://apps.apple.com/app/id6757975318 ; Geotag Alpha — https://apps.apple.com/app/id6450585140 ; GeoLink Pro — https://apps.apple.com/app/id6755872488 ; GRPS — https://apps.apple.com/app/id6502950232 ; GR Mint — https://apps.apple.com/app/gr-mint/id6751745136 ; Shutter – Fujifilm Camera Remote — https://apps.apple.com/us/app/shutter-fujifilm-camera-remote/id6478856044 ; Camera Remote Control Watch — https://apps.apple.com/us/app/id1598114789
- Apple: Core Bluetooth background processing — https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html ; `scanForPeripherals` — https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:) ; `CBConnectPeripheralOptionEnableAutoReconnect` — https://developer.apple.com/documentation/corebluetooth/cbconnectperipheraloptionenableautoreconnect ; `CBCentralManagerOptionRestoreIdentifierKey` — https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey ; `didModifyServices` — https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral(_:didmodifyservices:) ; `CBError.Code.leGattNearBackgroundNotificationLimit` — https://developer.apple.com/documentation/corebluetooth/cberror-swift.struct/code/legattnearbackgroundnotificationlimit ; QA1962 state restoration — https://developer.apple.com/library/archive/qa/qa1962/_index.html ; TN3187 scene life cycle — https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle ; watchOS background execution — https://developer.apple.com/documentation/watchkit/background-execution ; Enabling background sessions — https://developer.apple.com/documentation/watchkit/enabling-background-sessions ; watchOS app life cycle — https://developer.apple.com/documentation/watchkit/working-with-the-watchos-app-life-cycle ; `allowsBackgroundLocationUpdates` — https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates ; `pausesLocationUpdatesAutomatically` — https://developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically ; Handling location updates in the background — https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background ; WWDC23 "Discover streamlined location updates" — https://developer.apple.com/videos/play/wwdc2023/10180/ ; Apple DTS on `CLBackgroundActivitySession` on watchOS — https://developer.apple.com/forums/thread/775888 ; WWDC21 "Connect Bluetooth devices to Apple Watch" — https://developer.apple.com/videos/play/wwdc2021/10005/ ; WWDC22 "Get timely alerts from Bluetooth devices on watchOS" — https://developer.apple.com/videos/play/wwdc2022/10135/ ; WWDC24 "What's new in watchOS 11" — https://developer.apple.com/videos/play/wwdc2024/10205/ ; WWDC24 "Extend your app's controls across the system" — https://developer.apple.com/videos/play/wwdc2024/10157/ ; WWDC25 session 334 (watch controls) — https://developer.apple.com/videos/play/wwdc2025/334/ ; Enabling Double Tap — https://developer.apple.com/documentation/watchos-apps/enabling-double-tap ; `handGestureShortcut` — https://developer.apple.com/documentation/swiftui/view/handgestureshortcut(_:isenabled:) ; ActivityKit — https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities ; `LiveActivityIntent` — https://developer.apple.com/documentation/appintents/liveactivityintent ; `ForegroundContinuableIntent` — https://developer.apple.com/documentation/appintents/foregroundcontinuableintent ; `supportedModes` — https://developer.apple.com/documentation/appintents/appintent/supportedmodes ; Adding interactivity to widgets — https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities ; Creating controls — https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system ; Action button on Apple Watch Ultra — https://developer.apple.com/documentation/appintents/actionbuttonarticle ; `isFrontmostTimeoutExtended` (deprecated watchOS 7) — https://developer.apple.com/documentation/watchkit/wkextension/isfrontmosttimeoutextended ; `WKInterfaceDevice.play(_:)` — https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:) ; `WKRunsIndependentlyOfCompanionApp` — https://developer.apple.com/documentation/bundleresources/information-property-list/wkrunsindependentlyofcompanionapp ; `NSBluetoothAlwaysUsageDescription` — https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription ; Accessory Design Guidelines R31 — https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf ; App Privacy Details — https://developer.apple.com/app-store/app-privacy-details/ ; Privacy manifest files — https://developer.apple.com/documentation/bundleresources/privacy-manifest-files ; Required-reason APIs — https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api ; App Review Guidelines — https://developer.apple.com/app-store/review/guidelines/ ; Apple Platform Security, Bluetooth cross-transport key derivation — https://support.apple.com/guide/security/sec82597d97e/web ; Apple Watch AssistiveTouch — https://support.apple.com/guide/watch/apdec70bfd2d/watchos ; watchOS reduced reconnection range report — https://developer.apple.com/forums/thread/847700 ; forum report on BLE disconnects inside a workout — https://developer.apple.com/forums/thread/844843 ; watchOS pairing IO capability report — https://developer.apple.com/forums/thread/100266 ; Nordic CoreBluetoothMock — https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock
