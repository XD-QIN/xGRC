# GoPro and RICOH THETA support

Date: 2026-11-03. Adds two remote-only brands, GoPro HERO9 and later and
RICOH THETA X / A1. Both are built from the makers' own published Bluetooth
specifications, not from reverse-engineered traffic. Neither has run against a
real camera yet. This round sits on top of the Panasonic LUMIX commit
([11-03-26_panasonic-lumix-support-01.md](11-03-26_panasonic-lumix-support-01.md)).

## Why these two

The open-source search of the same day ranked new brands by what an iPhone or
Apple Watch can actually do as a Bluetooth central, and by license.

- **GoPro**: GoPro publishes the Open GoPro BLE spec, and its SDKs are MIT.
  An iOS app (kmatzen/facett, MIT) already drives HERO cameras over BLE.
- **RICOH THETA**: Ricoh publishes the THETA Bluetooth API and an MIT
  client with an iOS build.
- **Left out:**
  - DJI Osmo: dropped for good by the maintainer. The protocol documents sit
    under DJI's SDK EULA, and DJI's demo files call themselves proprietary.
  - Insta360: the phone would have to act as a BLE peripheral sending
    manufacturer-data adverts, which iOS can't do.
  - Nikon SnapBridge geotagging: the first pairing needs a Bluetooth Classic
    bond.
  - Blackmagic: video only.

No code was copied from either SDK. The drivers are written from the
documented facts (UUIDs, byte layouts, command IDs), and the sources are
credited in the code, the protocol reference and the README.

## What changed

- `CameraKit/Drivers/GoProDriver.swift`: the `GoPro` layout, message builders
  and packet accumulator, and `GoProDriver` (id `gopro`, new brand `.gopro`).
  - **Matching:** the 16-bit `FEA6` service.
  - **Connect (pair and every reconnect):**
    - Subscribe to the command response. The first time, this raises the
      system pairing dialog, with the camera on Connect Device › GoPro Quik App.
    - Send Set Third Party Client Info (`01 50`).
    - In remote sessions, load the Photo preset group (`04 3E 02 03 E9`), so
      a press is always one photo and never starts a video.
    - Start the 3-second keep-alive (`03 5B 01 42` on the settings
      characteristic). It stops on disconnect.
  - **Shot:** Set Shutter on (`03 01 01 01`), then wait up to 3 s for the
    response `01 00`. That response is the camera accepting the shutter, so
    GoPro shots count as **confirmed**. An error status (busy, for example)
    leaves the shot unconfirmed.
  - `releaseAll` is empty: a disconnect never sends shutter off, which would
    stop a video the user started on the camera.
  - No focus, no bulb, no geotag. GoPro has no command that takes a
    location.
- `CameraKit/Drivers/ThetaDriver.swift`: the `Theta` layout and
  `ThetaDriver` (id `theta`, brand `.ricoh`).
  - **Matching:** the client's name pattern (eight digits, or two letters
    and eight digits), or the Camera Control Command v2 service. The
    registry checks THETA before the Ricoh GR because both use the Camera
    Information service UUID.
  - **Connect:**
    - Discover the control service.
    - Read the model string, and refuse V and Z1 with `unsupported`. Their
      Bluetooth API needs a one-time registration over the camera's Wi-Fi,
      which xGRC doesn't do.
    - Subscribe to the state notification (logged).
    - In remote sessions, write `{"captureMode":"image"}`.
    - No bond.
  - **Shot:** write `{"name":"camera.takePicture"}`. The state JSON isn't
    decoded yet, so shots count as **assumed**.
- `DriverRegistry.standard` adds `ThetaDriver` (before `RicohDriver`) and
  `GoProDriver`. `CameraBrand` gains `gopro`.
- `SimulatedBodies`: `gopro(shutterStatus:)` answers every command with
  `02 <id> <status>`. `theta(model:)` serves a model string.
- `BrandText`: pairing steps for both brands, and a shutter note for each
  saying the camera is switched to photo/still mode on connect. The four new
  strings are machine-translated into all twelve other languages and need a
  native review, like the rest.
- Docs: protocol reference sections *GoPro (HERO9 and later)* and *Ricoh
  THETA X / A1*, two support-matrix rows in the product spec, README table
  and acknowledgements. The user agreement now says GoPro and Ricoh publish
  their protocols but don't endorse the app. The README now says only Sony
  has been tried on a real body.

## Tests

`GoProDriverTests`:

- matching
- the exact bytes of every message and the UUID base
- the accumulator on general, 13-bit and 16-bit headers and continuations
- the connect order, and no preset load in geotag-only sessions
- the shutter confirmation on success and none on an error status
- the keep-alive running and stopping

`ThetaDriverTests`:

- matching, including a THETA that also advertises the GR's info service
- still mode and the takePicture JSON
- no options write in geotag-only sessions
- Z1/V refused

## Device test (Phase 6 list)

GoPro (any HERO9–HERO13):

1. Pair from Connect Device › GoPro Quik App. Does subscribing raise the
   iOS dialog, or is a later write needed?
2. A shot from the phone and the watch shows **Confirmed**, and a photo is
   on the card.
3. Start from a video preset: does the Photo preset load, and does the
   press take a photo?
4. Leave it connected for 10 minutes: does the keep-alive stop the camera
   powering off? Then power-cycle the camera: does it reconnect by itself?
5. A shot while the camera is busy (just after a burst): the result should
   be unconfirmed, not a crash or a stuck shot.

RICOH THETA X:

1. Turn Bluetooth on and check that the camera shows up under its numeric
   name and connects without a pairing dialog.
2. A shot takes a 360° photo. Start from video mode to check the still-mode
   write.
3. Capture the state JSON after a shot from the transcript, so a later round
   can decode `_captureStatus` / `_capturedPictures` into a real
   confirmation.
4. A Z1 owner, if one turns up: confirm the "not supported" message.

## Not done

- App Store description texts (`App_Store_Intro/`) still list the original
  brands. Update them at the next release, along with LUMIX.
- THETA V/Z1 (Wi-Fi registration), GoPro movie button, and decoding the
  THETA state JSON into shot confirmations.
