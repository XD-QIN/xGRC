# Phase 2 — Watch geotag

Companion to [plan § Phase 2](10-14-26_phased-plan-04.md#phase-2--watch-geotag-phone-at-home) and the [product spec](10-14-26_product-spec-01.md), [architecture doc](10-14-26_architecture-02.md) and [protocol reference](10-14-26_ble-protocol-reference-03.md). This file records what Phase 2 built and the device tests it adds to the [Phase 6 device test pass](10-14-26_phased-plan-04.md#phase-6--device-test-pass).

**Status (2026-10-15):** code complete. Its package tests pass on Linux with Swift 6.1: 55 for the whole package, 24 of them new. `CoreLocationSource` was type-checked against a stub of the Core Location API. The Geotag page and the rest of the Apple-only code are first compiled at the start of Phase 6.

---

## What was built

| Piece | Where | What it does |
|---|---|---|
| Location types | `CameraKit/Core/Location.swift` | `GeoFix` (altitude above mean sea level), `LocationLinkMode` (push or pull), `KeepAlivePolicy`, `GeotagRules` (per-brand fix age, minimum interval, send time vs fix time) |
| Driver location calls | `CameraDriver` | `startLocationLink`, `stopLocationLink`, `keepAlive`, `syncClock`, `updateLocation`, `geotagRules`. Drivers without geotag keep the defaults, which throw `unsupported` |
| Sony location link | `SonyDriver` | `DD01` advisory subscribed and decoded; `DD21` read to pick the 95-byte or 91-byte packet; `DD30` then `DD31` written only when not already `01`; `DD11` packets through the same serial write chain as shutter writes; stop writes `DD31` then `DD30` to `00`; ATT `0x9D` and `0x9F` mapped to *Location Info. Link off* and *busy*. A reconnect re-enables an active link, and a failure there never takes the remote down |
| Simulated camera | `FakeCamera` | The location service with `DD21`, the lock and enable values, `0x9D`/`0x9F` faults, older firmware without `DD30`/`DD31`, and `CC02` |
| `LocationKit` (new target) | `LocationSource`, `FixFilter`, `SimulatedLocationSource`, `CoreLocationSource` | Core Location with `startUpdatingLocation()`, best accuracy, `.otherNavigation`, background updates, no auto-pause, inside a `CLBackgroundActivitySession`. The simulated walk backs the Demo camera |
| `GeoTagStreamer` | `SessionKit` | Filters fixes (≤ 50 m, Sony ≤ 10 s old, never 3× worse than a recent good fix); pushes the first fix at once, then on the interval, and at once on movement beyond 10 m plus accuracy; turns amber after 30 s without a valid fix; pauses while the link is down and pushes as soon as it is back; runs the `CC02` keep-alive only when *Keep camera awake* is on |
| Session and coordinator | `CameraSession`, `SessionCoordinator` | One geotag stream per session, link loss and restore passed through, `startGeotag`/`stopGeotag`, the open-session record (`openGeotagSession`) and `restoreSession()` at launch |
| Settings | `AppSettings`, `CameraRecord` | Geotag interval (5–60 s), open-session flag, per-camera *Keep camera awake*. Records written by an older build still load: missing fields take their defaults |
| Watch UI | `GeotagView.swift`, `SessionView.swift`, `AppModel.swift` | The Geotag page between Shutter and Settings: GPS dot and accuracy, session timer, last push, pushes, altitude, Start/Stop and one message line. Settings gains the interval and, for Sony, *Keep camera awake*. Launch re-opens an open geotag session |

---

## Decisions and defaults

1. **`updateLocation` takes the time zone.** The spec listed `updateLocation(_:time:)`. Sony's 95-byte packet needs the standard offset and the DST in effect, so the call is `updateLocation(_:time:zone:)`, and the spec's code block now matches.
2. **`syncClock` is a no-op on Sony.** The `DD11` packet carries the time; the camera sets its clock from it when its own auto-time setting is on.
3. **The wake-up budget question stays open until Phase 6.** Until it is measured, notifications during a location session are assumed to count against the budget. The streamer sends only what the interval needs, and the only notifications the Sony location link causes are `DD01` advisories.
4. **Remote and geotag on older Sony bodies.** The spec keys the Remote-or-Geotag choice on the model code, but no verified list of model codes exists yet. For now the Geotag page tells Sony users that bodies older than the α7 IV pause location while *Bluetooth Rmt Ctrl* is on. The modal comes when Phase 6 records real model codes.
5. **The Geotag page shows the latest fix,** accepted or not, so accuracy is visible while the GPS settles. Only fixes that pass the filter are sent.
6. **Location permission is *While Using*.** The background activity session keeps updates flowing with the wrist down, and the usage string is already in the watch target.

---

## Device tests (run in Phase 6)

Record results in `docs/support/<brand>-<model>.md` (template in [Phase 1 doc](10-15-26_phase-1-watch-remote-01.md#support-record-template)) and every problem in the pass's issue list.

| # | Test | How | Record |
|---|---|---|---|
| 1 | Watch-only walk | Phone at home. Start geotagging, wrist down, take 20 photos over 30 minutes while walking | EXIF on the camera or the Mac: local time correct, position plausible |
| 2 | Tripod | 30 minutes stationary with the wrist down | Pushes keep coming (count in the transcript); the link holds |
| 3 | Long walk | 2 hours, phone at home | Reconnects (target ≤ 1 per 30 min) and watch battery before and after (target ≤ 15 %/h) |
| 4 | Wake-up budget | Read the transcript from test 3 | Any `backgroundBudget` notes while the location session ran? Write the answer into the spec's watch runtime row |
| 5 | Relaunch | Force-quit mid-session and relaunch; then crash a debug build | The session comes back by itself on relaunch; Core Location relaunches the app after the crash |
| 6 | With a workout | Start an Apple Workout, then geotag | Pushes continue; which app comes up on wrist raise |
| 7 | Keep camera awake | 10 minutes with it on, 10 with it off | Shots untagged after the camera wakes in each mode |
| 8 | Location setting off | Turn *Location Info. Link* off on the camera, start geotagging | The message "Turn on Location Info. Link on the camera"; ATT `0x9D` in the transcript |
| 9 | Another device | Start location in Sony's own app first, then on the watch | The busy message; ATT `0x9F` |
| 10 | Older body | Any Sony body before the α7 IV, with *Bluetooth Rmt Ctrl* on | Do photos get tagged? Record the model code from the transcript's scan line for the Remote-or-Geotag list |
| 11 | Packet form | Any body | `DD21` bytes and the packet length (91 or 95) from the transcript |

### Phase 6 bars for this part

- [ ] 20 photos with correct GPS EXIF from a watch-only walk
- [ ] The tripod run and the 2-hour walk are recorded with reconnect count and battery figures
- [ ] The wake-up budget question is answered and written into the product spec

---

## Known gaps

- **Geotag Smart Stack tile and the Geotag page's "last push" colour** (red after 30 minutes, mirroring Fujifilm's icon) arrive with the Phase 3 tile work.
- **Pull model (Fujifilm)** is in the streamer's design (`LocationLinkMode.pull`) but has no driver until Phase 5.
- **The Remote-or-Geotag modal** waits for verified model codes (decision 4).
