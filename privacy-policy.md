# xGRC Privacy Policy

*Last updated: 21 October 2026*

> **Draft.** The bracketed fields must be filled in and the text should be checked by someone qualified before App Store submission. It is published at <https://xdqin.com/xGRC/privacy-policy>.

xGRC is a Bluetooth camera remote and GPS geotagger for iPhone, iPad and Apple Watch, made by an independent developer ("we", "us"). This policy explains what the app does with your information. The short version: **xGRC collects nothing. It has no accounts, no analytics, no advertising and no servers, and nothing you do in it is sent to us.**

## What the app uses, and why

| Data | Why the app uses it | Where it goes |
|---|---|---|
| **Your location** (GPS) | To geotag your photos: the app sends your position and the current time to the camera you connected, and the camera writes them into each photo's EXIF data. | To your connected camera, over Bluetooth, and into the session's GPS track on your device (next row). It is never sent to us or to anyone else. |
| **GPS tracks** | So you can see where a session went and keep a record of it: each fix the app sends for geotagging is saved with its time, along with the time and place of each remote shot, one file per session, named by the session's start time. | Stored on the device in the app's own storage. You can view a track on a map (iPhone and iPad), export it as a CSV file, which leaves the device only where you send it, and delete it at any time. |
| **Bluetooth** | To find, pair with and control your camera (focus, shutter, bulb, intervalometer) and to send it location for geotagging. | Between your device and your camera only. |
| **Saved cameras and settings** | So the app remembers the cameras you paired, the pairing keys some cameras need, and your choices (mode, release delay, bulb time, auto disconnect, and so on). | Stored on the device in the app's own storage, with pairing keys in the iOS / watchOS Keychain. The iPhone, iPad and Apple Watch apps each keep their own copy; nothing is synced between them or to any cloud. |
| **Widget and Live Activity status** | So the Lock Screen, Dynamic Island, Smart Stack and controls can show the camera's name and connection state. | Written to a container shared only with xGRC's own widgets on the same device. |
| **Bluetooth transcript** | A technical log of the messages exchanged with the camera, used to diagnose cameras that do not work. | Kept in the app's memory while it runs and gone when the app closes. The app has no way to export or send it. |

You can use xGRC in *Remote only* mode, in which it never asks for or uses your location.

## What we do not do

- We do not collect, store, sell or share any personal data. The app makes no network requests to us or to any third party, apart from the Apple Maps tiles and the links you tap, described below.
- We do not use analytics, advertising, tracking or third-party SDKs.
- We do not use HealthKit, workouts, contacts, photos or the camera of your phone.
- The App Store privacy label for xGRC is **Data Not Collected**.

## Things handled by Apple, by your camera or by other sites

- **Maps.** On iPhone and iPad the Geotag screen shows a map drawn by Apple's MapKit, which loads map tiles from Apple. Apple's privacy policy covers that.
- **Links in About.** *Privacy Policy*, *User Agreement*, *Developer* and *GitHub* in the About screen open xdqin.com (the developer's website) or github.com in your browser, or in the watch's web view, only when you tap them. Those sites' own privacy policies cover the visit.
- **Crash reports.** If you have agreed to share analytics with developers in your device settings, Apple may pass anonymous crash reports and diagnostics to us through App Store Connect. You control this in *Settings › Privacy & Security › Analytics & Improvements*.
- **Your photos.** Location that the camera writes into a photo stays in that photo. Remove it with your camera's or your photo app's tools before you share a photo if you do not want its location known.
- **Bluetooth pairing.** Your camera keeps its own record of paired devices. Delete xGRC's device from the camera's menu to remove it.

## Your choices

- Turn location access off at any time in *Settings › Privacy & Security › Location Services › xGRC*, or use *Remote only* mode.
- Turn Bluetooth access off in *Settings › Privacy & Security › Bluetooth*.
- Use *Forget camera* in the app to delete a camera and its pairing keys, delete GPS tracks under *GPS tracks*, or delete the app to remove everything it stored.

## Children

xGRC is not directed at children and collects no data from anyone.

## Changes

If this policy changes, the new version will be published at the address above with a new date. Because the app collects nothing, a change could only matter if a future version added a feature that sends data, and that would be described here and in the App Store listing before it ships.

## Contact

Questions about privacy: [CONTACT EMAIL].
