# App Store screenshots

Seven captioned frames for iPhone, the iPhone Duo's outer and inner displays
and the 13" iPad, and seven plain Apple Watch captures. The layout is xMosaique's App Store
design (black canvas, two-line headline in Hanken Grotesk Bold, a device frame
around the capture).

| Folder | Size | App Store Connect slot |
|---|---|---|
| [`1290x2796/`](1290x2796) | 1290 × 2796 | iPhone 6.9" (also accepts 1320 × 2868) |
| [`1284x2778/`](1284x2778) | 1284 × 2778 | iPhone 6.5" |
| [`1398x2034/`](1398x2034) | 1398 × 2034 | iPhone Duo, outer display |
| [`2853x2007/`](2853x2007) | 2853 × 2007 | iPhone Duo, inner display, landscape: the app runs landscape there, with the sidebar (six frames, as on iPad) |
| [`2064x2752/`](2064x2752) | 2064 × 2752 | iPad 13" (six frames: the iPad's sidebar already shows the camera list) |
| [`watch-422x514/`](watch-422x514) | 422 × 514 | Apple Watch Ultra |
| [`watch-416x496/`](watch-416x496) | 416 × 496 | Apple Watch Series 46 mm |

The captions are listed with the rest of the listing copy in
[`App_Store_Intro/appstore_intro.md`](../App_Store_Intro/appstore_intro.md#screenshot-captions).

| # | File | Caption | Scene |
|---|---|---|---|
| 1 | `01-your-camera-remote.png` | A remote for your camera. No dongle, no maker app. | `session`: Sony connected, geotagging |
| 2 | `02-fired-means-fired.png` | It says fired only when the camera confirms it. | `shots`: 36 confirmed shots |
| 3 | `03-timed-bulb.png` | Set a bulb time. One tap, it closes itself. | `bulb`: a 2 min 30 s bulb counting down |
| 4 | `04-timelapse.png` | Timelapses with no cable to carry. | `timelapse`: 4 s × 360 frames running |
| 5 | `05-gps-in-every-photo.png` | Your phone's GPS, in every photo. | `geotag`: the Geotagging screen |
| 6 | `06-mirrorless-and-compact.png` | Made for mirrorless and compact cameras. | `cameras`: the camera list |
| 7 | `07-release-delay.png` | A release delay, hands off the camera. | `delay`: a 10 s delay counting down |

Watch, in order: `session`, `shots`, `bulb`, `timelapse`, `geotag`, `controls`
(the session's Settings page), `cameras`.

## Regenerating

```sh
cd AppStorePreview/tools
./capture.sh            # builds the Debug simulator app, captures every device
python3 render.py       # sources/ -> ../<size>/NN-name.png
```

`capture.sh` needs Xcode and XcodeGen; `render.py` needs Pillow. Both can run
for part of the set: `./capture.sh iphone ipad` (with `SKIP_BUILD=1` to reuse
the last build) and `python3 render.py 03-timed-bulb`.

```
tools/
  frames.json   the layout, the devices, the seven frames' captions and scenes
  capture.sh    simulator captures into sources/<device>/<scene>.png
  render.py     frames, paints out the status bar, sets the headline
  assets/       Hanken Grotesk Bold (SIL OFL), the caption face
  sources/      the captures
```

**To change a caption:** edit `lines` in `frames.json` and re-run `render.py`.
It warns if a line is wider than the device frame.

## How the screens are captured

The simulator has no Bluetooth, so a screenshot run launches the app with
`-StoreScreens <scene>` (`Apps/Shared/App/StoreScreens.swift`). The app then:

- connects to the simulated Sony body the package tests use (`FakeCamera`
  behind `DemoCentral`), saved as an ordinary Sony so it shows as one;
- starts from throwaway stores with four more saved cameras (Fujifilm, Ricoh,
  Canon, Nikon), onboarding done, and the Sony as the last session, which Auto
  reconnect reopens with geotagging on;
- takes its location from a fixed walk starting at Tunnel View, Yosemite;
- sets up the scene once the Sony is connected: 36 shots, a bulb or delay
  countdown, a running timelapse, or the camera list, Settings, Geotagging or
  the watch's Geotag and Settings pages.

**None of it is in a release build.** The launch argument is read only under
`#if DEBUG && targetEnvironment(simulator)`; on a device or in Release,
`StoreScreens.scene` is `nil` and the code that builds the simulated session is
not compiled.

The simulators are made by `capture.sh` on first use and named
`xGRC Shots …`, in dark appearance, with the status bar at 9:41 on iPhone and
iPad (watchOS has no status bar override, so the watch shows the time it was
captured).

## How the frames are built

`render.py` follows xMosaique's rules, measured at 1290 × 2796 (`base` in
`frames.json`):

- **Scale by the canvas height**, not a fit to the box: the vertical
  composition (baselines against the top of the device frame) is the tuned
  part; a different aspect is taken up by re-centring.
- **The screen box takes the capture's aspect**, so a capture goes in
  unstretched; the frame is its border and bezel around it, with an even width
  so it centres on a whole pixel. iPad gets a wider bezel and a smaller corner.
- **The status bar is painted out** in the colour the app draws around it
  (`paintOut`): the top band on iPhone and iPad (and the iPad's resize grabber),
  the clock and icons in the Duo outer display's right-hand rail.

## The real camera capture

Frame 1 is meant to be a screenshot from a real iPhone paired with a real Sony.
Save it as `tools/sources/iphone/01-real-sony.png` and re-run `render.py`:
frame 1 at both iPhone sizes uses it instead of the simulator's, cropped to
the screen box if it comes from a phone of another size, with its status bar
painted out. The Duo and iPad keep the simulator capture.

## The iPhone Duo's inner display

Xcode 27.1 has no command to unfold the Duo simulator: unfold
`xGRC Shots Duo` by hand, then `./capture.sh duo-inner`. It captures the
device's largest screen (`display` inner in `capture.sh`), which the app fills
in landscape with the iPad layout, and `render.py` frames it at 2853 × 2007
with the status rail on the right painted out. App Store Connect takes either
orientation of a display size.
