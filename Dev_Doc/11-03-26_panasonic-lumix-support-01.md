# Panasonic LUMIX support

Date: 2026-11-03. Adds a Panasonic LUMIX driver: focus, shutter, timed bulb
and GPS geotagging. Nothing here has run against a real LUMIX yet.

## Where it comes from

- **furble PR #282** (gkoh/furble, branch `feature/support-panasonic-lumix`,
  commit `fdf5809`, MIT). `Lumix.cpp` was written from HCI traces of an S5II
  and a BGH1. Its author says it is wholly untested for lack of hardware, and
  the one user in furble issue #247 (S5II) could not connect with furble.
  xGRC's driver is a Swift port of the protocol in that file, not a copy of
  its code.
- **tobiasbrummer/lux-lat-long-log** (MIT). An ESP32 GPS logger for the S5,
  verified on the camera: the handshake, the clock write and GPS writes are
  accepted, and a test position appears in the photo's EXIF. Two of its
  findings change the port (below).
- **Aikhjarto/LUMIX-G9II-Remote-Control**. G9II work by GATT handle. Its
  command bytes match furble's, and one of LUMIX Sync's own GPS writes in
  it is the golden vector in the tests.

## What changed

- `CameraKit/Drivers/LumixDriver.swift`: the `Lumix` GATT layout and packet
  builders, and `LumixDriver` (id `lumix`, brand `.panasonic`).
  - **Matching:** the session service or the location service in the
    advertisement. Panasonic manufacturer data alone is not enough (other
    Panasonic products use the same company ID); its flags byte is logged.
  - **Connect (pair and every reconnect):** subscribe to both ready
    notifications, write `MEI0`, write our name (`xGRC-xxxxx`), wait up to
    3 s for `01` on both ready characteristics, then, in sessions that
    geotag, set the camera clock. furble does not subscribe, wait or write
    the clock here; lux found that a shortened sequence makes an S5 drop
    the link, so the driver follows lux's verified order.
  - **No bond.** No S5 capture shows pairing at the Bluetooth level. The
    first write still gets the 60 s bonding window in case a body asks.
  - **Buttons:** focus `01` press, `02` release; shutter `04` press, `05`
    release, all on the control characteristic. A shot is `04`, 100 ms,
    `05`. Bulb holds `04` and closes with `05` then `02`. No acknowledgement
    is decoded, so shots show as *sent*, and Shoot with nothing held waits
    250 ms after the half-press, as on Canon Remote. Movie is not ported
    (only the G9II trace shows `06`/`07`).
  - **Geotag:** pushed, stamped with the fix time, at most once a second.
    16 bytes: GPS-epoch seconds, latitude and longitude × 10⁷, altitude in
    whole metres (0 below sea level), `'A'`, `00`.
  - **Clock:** 10 bytes, UTC date and time, then the zone's standard offset
    in minutes and a daylight-saving flag. This is lux's layout, generalised:
    in Central European summer time it gives exactly the bytes the LUMIX
    app sent and lux replayed (`3c 00 01`). Remote-only sessions never
    touch the camera clock.
- `DriverRegistry.standard` lists the driver; `CameraBrand` gains
  `.panasonic`.
- `SimulatedPeripheral.lumix(sendsReady:)` and `LumixDriverTests.swift`:
  matching, the two packets (golden vectors from the G9II and S5 traces plus
  Tokyo, Sydney and New York), the handshake order on pair and reconnect,
  remote-only leaving the clock alone, the ready timeout, the button bytes,
  and location push.
- `BrandText`: LUMIX pairing steps (*Setup › Bluetooth*: Bluetooth On,
  Pairing; *Location Logging* for geotags) and a pairing hint. Both strings
  are in all thirteen languages; camera menu names stay in English, as for
  the other brands. Machine drafts, like the rest of the catalog.
- Docs: a Panasonic LUMIX section in the protocol reference, a row in the
  product-spec matrix and the README table, Panasonic in the
  not-affiliated lines of the README and the user agreement.

## Where the sources disagree

| Point | furble | lux (S5, on camera) | G9II project | xGRC |
|---|---|---|---|---|
| `MEI0` tail | `00 01 00 00` | `00 03 0B 54` (counter + check value, not verified by the camera) | 20-byte challenge response instead | furble's |
| Wait for ready notifications | no | yes, required | — | yes, 3 s, then goes on |
| Clock write | after every GPS write, UTC, tail `00 00 00` | in the handshake, UTC, tail `3C 00 01` | local time, tail `00 3C 00` | in the handshake, UTC + standard offset + DST flag |
| Control `01` every 3–4 s | — | seen from LUMIX Sync | — | not sent |

## Device test

Untested on any camera. On a LUMIX (any of S5, S5II, BGH1, G9II, or newer):

1. **Scan:** the camera shows up under its name in Add camera while it is in
   its Bluetooth pairing screen. If it does not, the advertisement carries
   neither service, and matching needs the manufacturer data or the name.
2. **Pair:** the connect gets through `MEI0` and the name. Note whether iOS
   shows a pairing dialog, whether the camera asks for anything, and whether
   both ready notifications arrive (transcript).
3. **Remote:** single tap focuses, double tap shoots, a timed bulb opens and
   closes. Try AF-S and MF.
4. **Geotag:** a photo carries the right position, altitude and GPS date and
   time. Check the camera clock afterwards, in a zone with daylight saving
   and one without: if it is off by the zone offset, the clock tail is the
   wrong layout (try the G9II one).
5. **Reconnect:** turn the camera off and on, and wait 20 minutes with the
   app closed, then reconnect. The camera's address is private and, without
   a bond, iOS may see it as a new device. If the saved camera no longer
   reconnects, xGRC needs a find-by-name fallback for this brand.
6. **Remote only:** the camera clock is not changed.
7. **G9II and other newer bodies:** if the camera drops the link after
   `MEI0`, it wants the challenge response, which is not implemented.
