# GPS track log

Every session that geotags keeps a record of where it went: each fix, with
its time, saved on the device. A track can be shown on a map (iPhone and iPad)
and exported as a CSV file (iPhone, iPad and Apple Watch).

## What is recorded

- **One track per camera session**, started when the session is installed
  (pair, open, or the Auto reconnect resume at launch) and ended by *End
  session*, auto disconnect or forgetting the camera. Stopping and starting
  geotagging inside a session adds to the same track.
- **Every fix the geotag filter accepts** (`GeoTagStreamer.validFixes()`):
  accurate and fresh enough to send to the camera, whether or not a push went
  out at that moment. Rejected fixes (too coarse, too old) are left out, so
  the track is what the camera could have been given.
- **No file until the first fix.** A Remote only session, or one where
  geotagging never got a fix, leaves nothing behind.
- **Every remote shot** (each press that went out: `ShutterSnapshot.sent`
  going up, so taps, Double Tap, the release delay, bulb, timelapse frames and
  Shortcuts alike) adds a row at the session's last fix, with the shot's time
  and `shot` 1 (added 2026-10-21). A shot with no fix in the last 120 s, or
  before the first fix, is not placed.
- Each device records its own tracks; the watch's stay on the watch.

## The file

`Application Support/xGRC/Tracks/yyyy-MM-dd-HH-mm-ss.csv`, named by the
session's start time in the device's time zone, e.g.
`2026-10-21-09-54-36.csv`. The track's name in the app is the same string.
Two sessions started in the same second get `-2`, `-3`… after the name.

```
timestamp,latitude,longitude,altitude_m,horizontal_accuracy_m,shot
2026-10-21T13:54:36.000Z,37.7158500,-119.6772200,1347.0,5.0,0
2026-10-21T13:54:41.000Z,37.7158500,-119.6772200,1347.0,5.0,1
```

- `timestamp` is the fix's own time in UTC, ISO 8601 with milliseconds, so a
  track reads the same in any time zone and lines up with the camera's GPS
  EXIF (which is UTC).
- Degrees to seven places (about 1 cm), metres to one place; no altitude is an
  empty field.
- `shot` is 1 for a remote shot and 0 for a fix. Tracks recorded before the
  column was added have five columns and read as fixes.
- One line is appended per row (`TrackStore`, Persistence), so a long session
  costs no rewrites, and a crash loses at most the line being written. A line
  cut short is skipped when the file is read.

The CSV is the whole record: export shares the file itself (`ShareLink`),
under its own name.

## Where it shows

| | iPhone and iPad | Apple Watch |
|---|---|---|
| Entry | *GPS tracks* on the camera list (the sidebar on iPad) | *GPS tracks* on the camera list |
| List | Name, point count and duration; *Recording* on the current session's track. Swipe or Edit to delete; long-press to export | Name, *Recording* on the current track |
| Open | The map: a blue dot (`MapCircle`) per fix and an orange one (`Annotation`, the same size at every zoom) per shot, the camera fitted to the track, the summary and a GPS / Shot key below, *Export CSV* in the toolbar | Point and shot counts and duration, *Share CSV*, *Delete* |

**The map is iPhone and iPad only**, by decision (2026-10-21). Dots are sized
to the track, 1/500 of its extent between 1.5 m and 60 m, so they read as
dots at the zoom that fits it; zooming in separates fixes that merge at that
scale. A track longer than 4,000 fixes shows every n-th one on the map; the
CSV keeps them all.

## Privacy

Location is still never sent anywhere: tracks stay in the app's container and
leave the device only as a file the user exports. The privacy policy now has a
*GPS tracks* row and the delete path, and no longer says location is "not
saved after the session". The App Store privacy label stays **Data Not
Collected**, since nothing reaches the developer.

## Tests

`TrackStoreTests` (file name from the local start time, CSV rows, read back,
no file without a fix, same-second suffix, delete, a cut-off line) and
`SessionCoordinatorTests.gpsTrack` (a demo session's accepted fixes land in
one track, and nothing is written after *End session*). 120 + 61 package
tests pass.

## Screenshot mode

`-StoreScreens` seeds a two-hour track along Yosemite Valley; the `tracks`
scene opens the list and `track` its map.
