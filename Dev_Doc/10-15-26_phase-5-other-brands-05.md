# Phase 5 — Other brands

Companion to [plan § Phase 5](10-14-26_phased-plan-04.md#phase-5--other-brands) and the [product spec](10-14-26_product-spec-01.md), [architecture doc](10-14-26_architecture-02.md) and [protocol reference](10-14-26_ble-protocol-reference-03.md). This file records what Phase 5 built and the device tests it adds to the [Phase 6 device test pass](10-14-26_phased-plan-04.md#phase-6--device-test-pass).

**Status (2026-10-15):** code complete. The package has 120 tests, all passing on Linux with Swift 6.1. 35 of them are new: each brand's packets against golden vectors, its pairing or handshake on a simulated body, and the sequencer and geotag streamer running the new drivers. The app changes (per-brand pairing steps and wording) need the Apple SDK and are first compiled at the start of Phase 6.

Protocol details come from the [protocol reference](10-14-26_ble-protocol-reference-03.md). The full UUIDs it had shortened came from furble's driver sources (`gkoh/furble`, `lib/furble`).

---

## What was built

| Piece | Where | What it does |
|---|---|---|
| Fujifilm | `FujifilmDriver.swift` | Legacy firmware: writes the advertised token. Secure firmware: reads the status and writes it back with byte 3 = `0x20`. Both write the client name on every connect, as furble does. Then it subscribes the official app's notification set and sets a 10 s location sync cycle. A shutter value goes out as the camera's two writes (`01 00`, then the parameter) with nothing in between. Geotag is pull: the camera asks with `01 00` and gets one 23-byte answer. An answer whose timestamp is not newer than the last is skipped |
| Canon Remote | `CanonDrivers.swift` | Emulates a BR-E1: `0x03` + name, then one control byte (`0x4C` focus, `0x8C` shutter, `0x0C` release). Each write uses with-response only if the camera's characteristic allows it, else without |
| Canon Smartphone | `CanonDrivers.swift` | Identifies with name, our UUID and platform `0x01`, waits up to 60 s for Accept (`0x02`) or Cancel (`0x03`), then sends the final identity write and shoot mode `0x02`. Shutter is `00 01` / `00 02`. Geotag enables when the camera asks (`0x03`); the 20-byte packet goes out only after the camera says enabled (`0x02`) |
| Nikon Remote | `NikonRemoteDriver.swift` | The four-stage handshake on every connect, with our 8-byte ID kept in Keychain. Press `02 02`, release `02 00`. Bulb runs as Time: the first press opens, the next press closes. A camera set to pair a smart device is reported as unsupported |
| Ricoh GR | `RicohDriver.swift` | Pairing writes the shooting flavour, which brings up the passkey. A shot is flavour `0` then start with AF. Location reads *Store Location Info.* first and then follows its notifications. The 32-byte packet is stamped with the fix time, at most every 10 s |
| Shared driver plumbing | `CameraKit/Core/DriverLink.swift` | Discovery with required characteristics, writes chained in call order with timeouts, grouped writes, notification pumps, and an inbox the handshakes await |
| Simulated bodies | `CameraKit/Drivers/Simulated/` | `SimulatedPeripheral` is a configurable GATT server. `SimulatedBodies.swift` lays out each brand and answers as its camera is documented to: Canon's Accept, Nikon's stages, the Fujifilm status, Ricoh's switch |
| Pull-model geotag | `GeoTagStreamer` | When the driver's location link is `.pull`, nothing is pushed on a timer or on movement. Each camera request gets one answer, and a request that arrives before any fix is answered by the first valid fix. New status `waitingForCamera`: fixes are ready, but the camera has not asked |
| Brands without acks | `ShotScript.acknowledgesFocus`, `focusSettle` | Shoot with nothing held waits a 250 ms settle after the half-press instead of a 2 s focus ack that never comes, and never shows the back-button-AF hint |
| Bulb close on leaving | `ShotSequencer.sceneInactive` | An open bulb is closed with the brand's unlatch, not a plain release, so Nikon (Time) and Ricoh (stop) close it |
| App wording | `Apps/Shared/App/BrandText.swift`, both Add camera screens, `AppModel` | Pairing steps per brand, the confirm-on-camera line per brand, the location-off message per brand, "waiting for the camera to ask", and a standing note for Canon Remote (drive mode) and Nikon (Time). The gesture line and the iPhone's AF hold follow the camera's capabilities |
| Registry | `DriverRegistry.standard` | Sony, Fujifilm, Canon Remote, Canon Smartphone, Nikon Remote, Ricoh |

---

## Decisions and defaults

1. **The Fujifilm time packet is not sent.** The spec names its service and characteristic only by their first eight hex digits (`E872B11F-…`, `C52EDBCE-…`, from GeoShutter), and furble does not have it. NOT1 time requests are logged. The camera clock is still set by the camera itself or by the maker's app. Capability `clockSync` is not claimed.
2. **Ricoh shots are *assumed*, not acknowledged.** The spec lists capture status and AF status as ack sources, but no source gives their byte layout. Claiming an ack with a guessed layout would mark every shot "not confirmed" if the guess is wrong. Both are subscribed and land in the transcript. Phase 6 decodes them from a real GR, then the driver claims `ackShutter`.
3. **Canon Smartphone writes shoot mode `0x02`** (furble). CanonBLEIntervalometer writes `0x03`. The plan asked for a setting; it is a one-line constant (`Canon.shootMode`) instead, because the device test decides it once for everyone.
4. **Canon trigger state (`00030031`) and Nikon indications (`2084`) are logged, not decoded.** Both are research cells in the architecture doc's ack table; shots are timed presses until a capture decodes them.
5. **xGRC never turns on a camera's own location switch.** Ricoh's *Store Location Info.* and Canon's *Select GPS device* stay the user's choice. The Geotag page says which menu to open.
6. **Write type follows the camera on Canon.** furble writes with response and the spec says without, so the driver uses with-response wherever the characteristic allows it (errors are then reported), else without.
7. **Fujifilm and Nikon re-register on every connect,** as furble does. Sony's first-pairing-only rule (`EE01`) is unchanged.
8. **Capabilities follow the support matrix.** Canon Remote and Nikon Remote have no geotag session to keep the app alive, so they do not claim background shooting: no Live Activity shutter. Ricoh claims no bulb; a long press still sends start, then stop on the next tap.
9. **Phase 5 tooling is deferred.** The transcript converter (`Tools/Transcript/`) and the CoreBluetoothMock tests are useful once there are real captures, so they move to Phase 6.

---

## Device tests (run in Phase 6)

Run each with whichever of these cameras is on hand. Record results in `docs/support/<brand>-<model>.md` (template in [Phase 1 doc](10-15-26_phase-1-watch-remote-01.md#support-record-template)) and every problem in the pass's issue list.

| # | Test | How | Record |
|---|---|---|---|
| 1 | Fujifilm secure pairing | Camera in Pairing Registration; add it on the watch, then on the iPhone | Whether the watch can confirm the code (numeric comparison), the time to Paired, the camera's registered name |
| 2 | Fujifilm legacy pairing | Same on a legacy-firmware body | Token accepted; reconnect after power cycle |
| 3 | Fujifilm shutter | Tap, double tap, Shoot; in BULB with a 5 s bulb time, one tap | Each shot taken; whether 250 ms settle is enough for AF; the 100 ms hold |
| 4 | Fujifilm geotag | Geotag on, Location sync on, shoot 5 frames over 2 minutes | EXIF GPS on each frame; requests every 10 s in the transcript; "waiting for the camera" when Location sync is off |
| 5 | Fujifilm re-registration | Register XApp after xGRC, then open xGRC | That xGRC reports Pair again |
| 6 | Canon Remote | Pair as a wireless remote; drive mode 2 s/remote; tap, double tap; in Bulb with a 5 s bulb time, one tap | Each shot; the drive-mode note; with-response or without in the transcript |
| 7 | Canon Smartphone | Pair as a smartphone; Accept on the camera; shoot; geotag with Select GPS device › Smartphone | Shoot mode `0x02` works (else try `0x03`); EXIF GPS; the trigger-state notifications around each shot |
| 8 | Canon Smartphone Cancel | Choose Cancel on the camera | "The camera declined or did not answer" |
| 9 | Nikon Remote | Connection to remote › pair; shoot; shutter speed Time with a 5 s bulb time, one tap | Handshake time; serial; Time exposure opens and closes; `2084` indications per shot |
| 10 | Nikon SnapBridge refused | Camera set to pair a smart device | "Not supported" message, no hang |
| 11 | Ricoh pairing | Bluetooth on; add it on the watch and the iPhone | Whether the watch can enter or confirm the passkey |
| 12 | Ricoh shutter and status | Shoot 10 frames | Capture status and AF status bytes per shot, to decode the ack |
| 13 | Ricoh geotag | Store Location Info. off, then on | The off message; EXIF GPS with on; one packet per 10 s at most |
| 14 | Pairing steps | Follow each brand's Add camera text on the body tested | Correct the menu paths that differ |

### Phase 6 bars for this part

- Every brand on hand pairs from the watch and the iPhone, or its failure is recorded with the IO-capability finding (Fujifilm secure, Ricoh).
- Every shot on a no-ack brand is counted as sent, never as confirmed.
- Geotag EXIF is present on Fujifilm, Canon Smartphone and Ricoh frames taken while tagging.

---

## Known gaps

- Fujifilm time packet (decision 1) and Ricoh's date/time characteristic: neither UUID is known yet.
- Canon Remote movie (`0x08` mode) is not driven; Record is unsupported on that driver.
- The Mode picker does not yet stop Geotag on a Canon Remote or Nikon Remote camera; starting geotag there fails with "can't take locations over Bluetooth".
- Fujifilm's location interval is the camera's 10 s cycle; the Geotag page's interval setting does not apply to it yet.
- The Fujifilm 15 s silent-connection watchdog from the plan relies on the general reconnect policy; there is no Fujifilm-specific timer.
