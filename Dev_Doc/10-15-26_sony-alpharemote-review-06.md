# Sony: comparison with AlphaRemote

A review of [Staacks/alpharemote](https://github.com/Staacks/alpharemote) (α-Remote, an Android Bluetooth remote for Sony bodies, read at commit `4a950a8`, v1.4) against xGRC's Sony support (`SonyDriver`, `FakeCamera`, `ShotSequencer`, `CoreBluetoothTransport`). It covers the shutter, focus, bulb, button release and ack codes, pairing and bonding, the location link, reconnects, model quirks, and the features xGRC lacks.

**Licence.** AlphaRemote is GPL-3.0. xGRC was Apache 2.0 when this review was done (it moved to GPLv3 on 2026-10-21), so only protocol facts were taken and reimplemented. No code was copied. AlphaRemote is credited as a protocol source in the [protocol reference](10-14-26_ble-protocol-reference-03.md#references).

**Result.** One real bug was fixed: xGRC held the full press for the whole bulb time, but with a Bluetooth remote Sony's bulb is a toggle, so the shutter would never have closed. The `FF02` decoder was also made more tolerant. Everything else already matched AlphaRemote or goes further. The fixes are tested on the fake camera and need a Sony body in the [Phase 6 pass](10-14-26_phased-plan-04.md#phase-6--device-test-pass).

---

## Side by side

| Area | AlphaRemote | xGRC before | Verdict |
|---|---|---|---|
| Remote service, `FF01` writes | With response; `01 xx` buttons, `02 xx step` jogs | Same, with response | Same |
| Button codes | Half `06/07`, full `08/09`, record `0E/0F`, AF-ON `14/15`, C1 `20/21` (up/down) | Same codes in the reference; the driver sends half, full and record | Same |
| Shot order | Half-down, full-down, wait for shutter, full-up, half-up | Half-down, focus ack (2 s, optional), full-down, shutter ack (3 s), full-up, half-up | Same order. xGRC waits for focus first, like AlphaRemote's "Trigger on focus", which avoids bursts in continuous drive |
| `FF02` status | Code in byte 1 (`3F`, `A0`, `D5`), state = byte 2 bit `0x20` | Exact 3-byte match | **Changed**: decode by code and bit, as AlphaRemote does |
| ATT error `0x90` | "Bluetooth Rmt Ctrl is off"; any later notification clears the warning | Mapped to `remoteControlOff` | Same |
| **Bulb** | Toggle: press, wait for `A0 20`, release, count down, press and release again | Held press: `01 09`, count down, `01 08` `01 06` | **Bug, fixed.** See below |
| Pairing | Companion-device scan on company `0x012D`, `03 00`, tag `22`, bit `0x40` (pairing); protocol byte ignored (`0x64` older, `0x65` 2023+); `createBond()` | Same fields; pairable = bits 7 and 6; `EE01` registration in pairing mode only | Same, xGRC stricter on bit 7 |
| Remote-enabled bit | Its α6400 flips `0x04` of the flags byte with the remote setting (`EC` on, `E8` off); deliberately not filtered | Not filtered; remote availability from `CC09` or `0x90` | Same |
| Bond | Connects only when bonded; on unbonding shows "not bonded" and reconnects when bonded again | Bond removed → *Pair again* | Same |
| Service Changed | Newer bodies send it a few hundred ms after connecting; rediscover and reset the queue | `didModifyServices` → session re-registers | Same |
| Reconnect | Android companion presence and `autoConnect`; tolerates short drops without tearing down | Pending connect with auto-reconnect, foreground rescan, re-register | Same idea; xGRC also closes an open bulb and releases every button first |
| Location link | Not implemented; its README says the α6400 cannot run the remote and geotagging together | `DD01`/`DD21`/`DD30`/`DD31`/`DD11`, Remote-or-Geotag choice for pre-α7 IV bodies | xGRC goes further; the α6400 note agrees with xGRC's exclusivity rule |
| Release on cancel | Releases every button and jog it knows | Releases full and half; record is press/release as a pair | Enough for what xGRC sends |

## The bulb bug

Sony's help guides for the α7R IV, α7 IV, α7CR, ZV-1 and RX100 VII all say that with the Bluetooth remote "you can start bulb shooting by pressing the shutter button on the remote commander. To stop bulb shooting, press the shutter button on the remote commander again." AlphaRemote's bulb timer is built the same way. xGRC's Sony `latch` pressed and held `01 09` and its `unlatch` released it. On a real body that opens the shutter on the press and ignores the release, so a timed bulb would have stayed open until the user stopped it on the camera.

Now:

- `latch`: `01 09`, wait for the shutter ack, `01 08`, `01 06` (after the usual `01 07` and focus wait).
- `unlatch`: `01 07`, `01 09`, `01 08`, `01 06`. This closing press is not counted as a shot.
- `unlatchToggles` is on for Sony, as it already was for Nikon Time. The sequencer sends the closing press on the timer, on a tap, on leaving the app, on Stop in a timelapse and after a reconnect.
- **New guard in the sequencer:** a toggling close goes out only if the opening press drew the shutter ack. Without the ack (AF could not focus, or the press never reached the camera) the shutter is assumed shut. A second press would open a bulb nobody closes, so the result is shown as not confirmed and nothing else is sent. Nikon has no ack, so it is unaffected.
- Outside BULB mode each press takes a normal photo, so a timed bulb takes two. The existing "set the camera to BULB" hint covers it, and the device test list now records it.

`FakeCamera` gained a `bulbMode` that behaves like this (press opens, next press closes, release does nothing). New tests cover the open and close bytes, closing on the timer, on a tap and on Stop in a timelapse, closing after a link drop, and that nothing follows an unacknowledged open.

## What xGRC lacks

These are features, not bugs, and were not added. They are protocol facts already in the reference, if wanted later:

- **Zoom and manual focus jogs** (`02 44/45`, `02 46/47`, `02 6A/6B`, `02 6C/6D` with a speed byte). AlphaRemote uses zoom speed `0x10`–`0x7F` and focus `0x00`–`0x7F`, and uses timed focus jogs for focus bracketing. Focus jogs need MF on the camera and AF on the lens switch.
- **AF-ON and C1 buttons** (`01 14/15`, `01 20/21`). C1 does whatever the user assigned to it on the camera, which makes it the most flexible button. The plan's "After 1.0" list already has an AF-ON focus option.
- **"Trigger once"**: full press held until the shutter ack, with no focus wait. Fastest in MF, but bursts in continuous drive. xGRC's focus-first shot is the safer default.
- **Hardware key bindings** (Android volume keys and generic Bluetooth remotes as triggers). On Apple platforms the Action Button and Double Tap fill this role.

## Not changed, on purpose

- **Focus wait before the full press.** AlphaRemote's FAQ explains the trade-off: holding the full press until the shutter ack works in every focus mode but bursts in continuous drive, while waiting for focus first does not burst but stalls in MF. xGRC waits up to 2 s for focus (optional), then fires. MF costs that 2 s. A focus mode setting could remove it later.
- **Advertisement low bits.** Both apps ignore them; the support table in Phase 6 records them.

## Device tests added to Phase 6

These are listed under "Checks from the AlphaRemote comparison" in the [plan](10-14-26_phased-plan-04.md#test-list): a timed bulb in BULB, the closing press, EXIF exposure time; bulb with AF that cannot focus (no second press); bulb across a link drop; bulb frames in a timelapse and Stop; unusual `FF02` values; Service Changed on newer bodies.

## Testing note

The Swift toolchain could not be installed in this session (the download host is blocked), so `swift test` was not run here. The tests were updated by hand to match the new byte sequences. Run `cd Packages/xGRCCore && swift test` on the Mac before merging.
