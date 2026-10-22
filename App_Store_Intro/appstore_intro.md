# xGRC — App Store Copy

Ready-to-paste text for App Store Connect. Character limits are noted next to
each field; counts for the supplied copy are given in brackets.

**One App Store record** carries the iPhone and iPad app and the Apple Watch
app, which runs on its own (`WKRunsIndependentlyOfCompanionApp`), so people can
install either or both. The listing has to sell all three.

**Thirteen languages, like xMosaique.** The app ships English plus twelve
more (`Apps/Shared/Localization/Localizable.xcstrings`), chosen in
Settings › Language and English by default. The translated copy lives beside
this file, one document per language, ten files for twelve App Store Connect
localizations:

| File | App Store Connect localization(s) | App locale |
|---|---|---|
| [appstore_intro_CN.md](appstore_intro_CN.md) | Chinese (Simplified), Chinese (Traditional) | `zh-Hans`, `zh-Hant` |
| [appstore_intro_ES.md](appstore_intro_ES.md) | Spanish (Spain), Spanish (Mexico) | `es`, `es-419` |
| [appstore_intro_PT-BR.md](appstore_intro_PT-BR.md) | Portuguese (Brazil) | `pt-BR` |
| [appstore_intro_FR.md](appstore_intro_FR.md) | French | `fr` |
| [appstore_intro_DE.md](appstore_intro_DE.md) | German | `de` |
| [appstore_intro_IT.md](appstore_intro_IT.md) | Italian | `it` |
| [appstore_intro_JA.md](appstore_intro_JA.md) | Japanese | `ja` |
| [appstore_intro_KO.md](appstore_intro_KO.md) | Korean | `ko` |
| [appstore_intro_HI.md](appstore_intro_HI.md) | Hindi | `hi` |
| [appstore_intro_ID.md](appstore_intro_ID.md) | Indonesian | `id` |

**All twelve are machine drafts**, and so are the app's own translations:
have a native speaker read each before submitting. **Keep every file in
step: a change here that touches a claim needs the same change in all of
them.** Review notes, privacy answers and TestFlight text stay in English.

**Written for 1.0**, the first release, on 2026-10-21 against
the 1.0.0 source. The project
is set to `MARKETING_VERSION = 1.0.0`, build 1, for the first archive. Re-read every claim against the archived commit before
submitting (see [Copy notes](#copy-notes)).

**Still open before submitting:**

1. **App Review has no camera.** The Demo camera was removed from Settings on
   2026-10-16, so a reviewer cannot connect anything. The review notes below
   ask for a demo video; record it on device and add its link (see
   [Notes for App Store Review](#notes-for-app-store-review)).
2. **The privacy policy is a draft** with `[CONTACT EMAIL]` unfilled
   (`privacy-policy.md`), and the Support URL needs a page with a contact
   address.
3. **The TESTED ON line in the review notes is a placeholder.** Fill it from
   the device test pass, with the camera bodies actually used.

---

## At a glance

| Field | Value |
|---|---|
| App name | xGRC - Camera Remote & Geotag |
| Subtitle | Shutter and GPS on your wrist |
| Primary category | Photo & Video |
| Secondary category | Utilities |
| Age rating | 4+ |
| Requires | iOS 17.0 or later (iPhone, iPad); watchOS 10.0 or later (Apple Watch) |
| Languages | 13: English, Chinese (Simplified, Traditional), Spanish (Spain, Latin America), Portuguese (Brazil), French, German, Italian, Japanese, Korean, Hindi, Indonesian |
| Price | Set in App Store Connect; no subscription, no in-app purchase |

---

## App name (30 characters)

```
xGRC - Camera Remote & Geotag
```
[29]

The name under the icon stays `xGRC` (`CFBundleDisplayName` in
`project.yml`); this is only the listing name, which needs no build to change.
Apple indexes the name and subtitle for search, so "camera", "remote",
"geotag", "shutter", "GPS" and "wrist" need not be bought again as keywords.

Alternates:

```
xGRC: Camera Remote & GPS Tag
```
[29]

---

## Subtitle (30 characters)

```
Shutter and GPS on your wrist
```
[29]

Alternates, if the above tests poorly:

```
Bluetooth shutter, watch & GPS
```
[30]

```
Your camera’s remote, no cable
```
[30]

---

## Promotional text (170 characters — editable without a new build)

```
Fire your camera from iPhone, iPad or Apple Watch: timed bulb, release delay, timelapses, and GPS in every photo. No dongle. No account. Nothing collected.
```
[155]

---

## Description (4,000 characters)

Paste this block verbatim. Paragraphs are single long lines on purpose: App
Store Connect keeps every newline, so a wrapped paragraph would show on the
store page as broken half-sentences.

```
xGRC turns your iPhone, iPad and Apple Watch into a Bluetooth remote for your camera, and into its GPS. It talks straight to the Bluetooth built into Sony, Fujifilm, Canon, Nikon and Ricoh cameras: no dongle, no Wi-Fi, no maker app to wait for.

ONE TAP FOCUSES, TWO TAPS SHOOT
The shutter works the same everywhere. Tap once to focus, tap twice to shoot. Hold AF if you want focus locked while you wait for the moment.

IT SAYS FIRED ONLY WHEN IT FIRED
Where the camera confirms a shot, xGRC says Fired and counts it. Where the camera's Bluetooth has no confirmation, it says Sent instead. The confirmed and sent counters never pretend.

LONG EXPOSURES WITHOUT THE CABLE
• Timed bulb: set a time up to 99 min 59 s, tap once, and the shutter closes by itself when the countdown ends
• Release delay from 1 to 60 seconds, so your hand is off the camera when it fires
• Intervalometer for timelapses: interval, number of frames or until stopped, a start delay, and an optional shutter-open time

GPS IN EVERY PHOTO
xGRC sends your device's location and time to the camera, which writes them into each photo it takes. On iPhone it keeps going with the phone locked and shows in the Dynamic Island and on the Lock Screen. On Apple Watch it geotags on its own, with the phone left at home. Every session keeps its GPS track on your device, each fix with its time: see it as dots on a map on iPhone and iPad, and export it as a CSV file from any of them.

A REAL APPLE WATCH APP
Scan, pair, shoot and geotag from the watch, no iPhone needed. On Apple Watch Series 9, Ultra 2 and later, a Double Tap of your index finger and thumb fires the shutter, so the hand holding the camera can stay where it is. Turn on Tap to shoot and one tap on the screen focuses and shoots. A Smart Stack tile shows the session at a glance.

BUILT FOR THE FIELD
• Choose Remote + Geotag, Remote only or Geotag only
• Auto reconnect picks the session back up when the camera wakes or comes back in range
• Auto disconnect frees the camera after a quiet spell, 15 minutes unless you change it
• Shortcuts and Controls: Shoot, Focus, Start and Stop geotagging
• Light, dark or system appearance on iPhone and iPad
• Big, glove-friendly controls and clear haptics
• Thirteen languages, chosen in Settings

WORKS WITH
• Sony Alpha, ZV, RX and FX cameras with Bluetooth remote control
• Fujifilm X and GFX
• Canon EOS and PowerShot, in Remote or Smartphone pairing
• Nikon, in remote (ML-L7) mode
• Ricoh GR III, GR IIIx and GR IV
What each camera can do over Bluetooth differs: focus, bulb and geotagging are not available on every brand or mode. The full list is on the project's GitHub page, linked from About.

PRIVATE BY DESIGN
No account, no analytics, no ads, no servers. Your location goes only to your camera, over Bluetooth, and into tracks that stay on your device until you export or delete them. xGRC is open source under the GPLv3 licence.

xGRC is not affiliated with Sony, Fujifilm, Canon, Nikon or Ricoh. Brand names are trademarks of their owners.
```
[3,036]

**What is left out on purpose:** the in-app Bluetooth transcript (a
diagnostic, not a feature a shopper looks for), Keep camera awake (a Sony
geotagging option that keeps the camera's screen on), and the iPad's
sidebar layout.

**Every brand line is narrower than "supports".** The support matrix in the
README marks Canon Smartphone mode as two sources, Nikon as one, and Ricoh as
spec plus one implementation, and no feature is verified on every body. The
WORKS WITH paragraph names the modes and says plainly that features differ.
Widen it only from device results.

---

## Keywords (100 characters, comma-separated, no spaces)

```
intervalometer,timelapse,bulb,trigger,mirrorless,exif,geotagging,location,photography,dslr,release
```
[98]

Words in the name and subtitle (camera, remote, geotag, shutter, GPS, wrist)
are already indexed, so they are not here. **No brand names**: Sony, Fujifilm,
Canon, Nikon and Ricoh are trademarks, and keyword trademarks are a common
rejection. The Description names them as compatibility, which is allowed.

---

## What's New (4,000 characters) — version 1.0

The first version's What's New is not shown on the store page, but App Store
Connect still asks for it.

```
The first release of xGRC: a Bluetooth camera remote and GPS geotagger for iPhone, iPad and Apple Watch.
```
[104]

---

## Screenshot captions

**Seven frames, built** — see [AppStorePreview/](../AppStorePreview/README.md)
for the rendered PNGs at each store size and how to regenerate them. To change
a caption, edit `lines` in `AppStorePreview/tools/frames.json` and re-render.

1. **A remote for your camera. No dongle, no maker app.** — the session screen,
   Sony connected and geotagging. Becomes the real iPhone capture with a Sony
   once it is in `tools/sources/iphone/01-real-sony.png`
2. **It says fired only when the camera confirms it.** — Fired · confirmed,
   36 confirmed shots
3. **Set a bulb time. One tap, it closes itself.** — a 2 min 30 s bulb counting
   down
4. **Timelapses with no cable to carry.** — the intervalometer running
5. **Your phone's GPS, in every photo.** — the Geotagging screen with its map
6. **Made for mirrorless and compact cameras.** — the camera list (not on iPad,
   whose sidebar shows the list on every frame)
7. **A release delay, hands off the camera.** — a 10 s delay counting down

The Apple Watch screenshots carry no caption: App Store Connect takes them at
the watch's own resolution.

---

## App preview video script (15–30 seconds, no voiceover)

Shoot it on the real devices with a real camera: Apple rejects previews that
are mostly motion graphics or footage of anything but the app.

| Time | On screen | Caption card |
|---|---|---|
| 0–4s | iPhone: the camera list, tap the camera, Connected | *Your camera, on Bluetooth.* |
| 4–9s | Double tap the shutter; Fired · confirmed, the counter goes up | *Two taps. Fired, and it says so.* |
| 9–15s | Set a bulb time, one tap, the countdown runs and closes | *Timed bulb, one tap.* |
| 15–22s | Apple Watch: Double Tap with the camera in the other hand | *Or fire it from your wrist.* |
| 22–27s | Geotagging screen, the map and the pushes counting | *GPS in every photo.* |
| 27–30s | App icon and name | *xGRC* |

---

## Notes for App Store Review

[2,780 of 4,000.] This goes in **App Review Information → Notes** (4,000 characters). It exists
to stop one rejection: **the app does nothing visible without a camera, and
App Review has none.** The Demo camera that once answered this was removed
from Settings, so the notes rely on a demo video. Record one on device (pair,
shoot, bulb, watch Double Tap, geotag) and put its link where marked; Apple
asks for a video for hardware-dependent apps under guideline 2.1.

```
xGRC is a Bluetooth remote and GPS geotagger for cameras with built-in Bluetooth (Sony, Fujifilm, Canon, Nikon, Ricoh). iPhone and iPad run iOS 17 or later; the Apple Watch app runs on its own on watchOS 10 or later.

NO ACCOUNT OR LOGIN. Nothing needs credentials.

--- A CAMERA IS NEEDED TO TRY THE CORE FEATURES ---
The app controls a physical camera over Bluetooth Low Energy. Without one it shows the empty camera list and Add camera, which keeps scanning. A video of the whole flow on real hardware is here: [DEMO VIDEO LINK]

--- CORE REVIEW PATH (with a supported camera) ---
1. Turn on the camera's Bluetooth remote or smartphone pairing (Sony: Bluetooth Rmt Ctrl On and Pairing, in the camera's Network menu).
2. Open xGRC, allow Bluetooth, tap Add camera, tap the camera, and confirm on the camera.
3. On the session screen tap the shutter once to focus, twice to shoot. The counter says confirmed when the camera acknowledges the shot.
4. Geotagging starts from the Geotag row (allow Location). The camera writes the location into each photo.

--- APPLE WATCH ---
The watch app pairs and shoots without the iPhone. On Series 9, Ultra 2 and later with watchOS 11, a hand Double Tap fires the shutter while the Shutter page is on screen.

--- PERMISSIONS ---
* Bluetooth: to connect to and control the camera. Core feature.
* Location (When In Use): only to send position and time to the camera for geotagging, including with the screen locked during a geotag session. Never sent anywhere else. Not asked in Remote only mode.
* Notifications: optional; a shot or timelapse result that finishes while the app is not on screen.

--- CORRECT, THOUGH IT CAN LOOK LIKE A DEFECT ---
* "Sent" instead of "Fired": some cameras do not confirm a shot over Bluetooth, so the app reports it was sent rather than claim it fired.
* The screen stays on during a remote session on iPhone and iPad, so auto-lock does not cancel a release delay or stall a timelapse.
* Auto disconnect ends an idle session after 15 minutes by default, to free the camera and save battery.

--- PRIVACY ---
No backend, analytics, advertising or third-party SDKs; the App Privacy answer is Data Not Collected. Location goes only to the user's own camera over Bluetooth and into GPS tracks kept on the device (camera list > GPS tracks), which leave it only when the user exports a CSV. The only network use is Apple Maps tiles on the Geotag screen and links in About that open in the browser.

--- TESTED ON ---
[iPhone model and iOS version, Apple Watch model and watchOS version, camera bodies]

--- THIRD-PARTY MATERIAL ---
Not affiliated with any camera maker. The Bluetooth protocols follow open-source community work (furble, MIT), credited in the app's GitHub repository. Open source under GPLv3.
```

---

## App Privacy answers

| Question | Answer |
|---|---|
| Does the app collect data? | No — **Data Not Collected** |
| Location | Not collected: sent only to the user's own camera over Bluetooth, and kept on the device as GPS tracks the user can export or delete; never sent to the developer |
| Identifiers / usage / diagnostics | Not collected; crash reports come only through Apple if the user shares them |
| Tracking | No |

This holds because nothing leaves the device (product spec § Privacy). If a
"report a camera" upload is ever added, the label changes to Coarse Location
and Other Diagnostic Data (not linked, not tracking).

---

## Support and marketing URLs

Use the same links the app's About section opens (`AboutInfo.swift`), so the
store page and the app agree:

- **Privacy policy URL** — **required**: https://xdqin.com/xGRC/privacy-policy
  (guideline 5.1.1(i) wants it in App Store Connect and in the app; About
  links it).
- **Support URL** — https://xdqin.com, once it has a visible contact address
  and a few lines of help (pairing, *Pair again*, the support list). Apple
  checks that the page offers support. The GitHub issues page can be linked
  from it, but should not be the Support URL on its own.
- **Marketing URL** *(optional)* — https://github.com/XD-QIN/xGRC, or a page on
  xdqin.com.
- **License Agreement** — leave Apple's standard EULA. The user agreement at
  https://xdqin.com/xGRC/user-agreement is linked from About; pasting a custom
  EULA into App Store Connect only adds a surface to review.

Check that every link returns 200 before submitting; App Review clicks them.

---

## TestFlight — external beta

### Beta App Description (shown to every tester)

```
Thank you for testing xGRC.

xGRC is a Bluetooth remote and GPS geotagger for your camera, on iPhone, iPad and Apple Watch. It talks to the Bluetooth already in Sony, Fujifilm, Canon, Nikon and Ricoh cameras: one tap focuses, two taps shoot, a timed bulb closes by itself, and the release delay and intervalometer run from your phone or your wrist. Geotagging sends your location to the camera so every photo carries it. The watch app works without the iPhone, and on Series 9, Ultra 2 and later a Double Tap fires the shutter.

EXPECTED BEHAVIOUR, NOT BUGS
• "Sent" instead of "Fired": some cameras do not confirm a shot over Bluetooth.
• Sony bodies older than the α7 IV can use the remote or geotagging in one session, not both.
• On the watch, shooting needs xGRC on screen. Set Settings > General > Return to Clock > xGRC to After 1 Hour for long sessions.

WHAT WE MOST WANT TO HEAR
• Your camera model, and whether pairing worked the first time.
• Any shot the app called Fired that the camera did not take, or the other way round.
• Whether the photos carry the right location.
• Any crash, or a camera that stopped answering, with what you did just before.

Take a screenshot in the app and TestFlight will offer to send it with a note, or use Send Beta Feedback in the TestFlight app.

PRIVACY
No account, nothing collected. Your location goes only to your camera.
```

### What to Test (per build)

```
1. PAIR your camera from Add camera, on the iPhone and on the watch. Tell us the model.
2. SHOOT: tap to focus, double tap to shoot. Does the camera fire every time, and does the counter say confirmed?
3. TIMED BULB: set a bulb time (camera in BULB), tap once. Does it close on time?
4. RELEASE DELAY and INTERVALOMETER: does every frame fire?
5. GEOTAG: shoot a few photos with geotagging on. Is the location in them?
6. WATCH: Double Tap and Tap to shoot, with the screen awake and after the wrist drops.
7. RECONNECT: switch the camera off and on. Does the session come back by itself?
8. GPS TRACKS: after a geotag session, open Cameras > GPS tracks. Does the map match where you went, and does the exported CSV open in a spreadsheet?
```

---

## Copy notes

- **No brand names in the screenshot captions** (the maintainer's call,
  2026-10-21): "mirrorless and compact cameras" instead. Brand names the app
  itself shows in a screenshot stay.
- **Name brands only as compatibility.** "Works with" in the Description is
  fine; brand names in the name, subtitle or keywords invite a trademark
  rejection.
- **Do not overclaim support.** No body has a full device pass yet, and the
  support matrix's confidence column is real. Say what a brand can do only once
  a device result backs it, and keep the "differs by camera" sentence.
- **Say "fired" only for confirmed shots**, the way the app does. The whole
  pitch of acknowledged shooting is that the word means something.
- **Do not promise background shooting.** On the watch, shooting needs the app
  on screen; on iPhone it depends on the brand. The Dynamic Island shutter is
  shown only where the brand allows it.
- **Leave pricing out of the Description**; set it in App Store Connect.
- **The first three lines matter most**; the rest is behind "more".
- **Count every field before pasting** (App Store Connect counts characters,
  not bytes). This prints the length of every fenced block in this file:
  `python3 -c "import re,sys; [print(len(b), b[:40]) for b in re.findall(r'\`\`\`\n(.*?)\n\`\`\`', open(sys.argv[1]).read(), re.S)]" App_Store_Intro/appstore_intro.md`
