# Open-source release under GPLv3

Date: 2026-10-21. The repository was started again with a fresh history, so
that it can be public, and the licence changed from Apache 2.0 to GPLv3.

## What changed

- **Licence.** `LICENSE` is now the full text of the GNU General Public
  License, version 3. The README, the user agreement, the App Store listing
  copy in all thirteen languages and the Dev_Doc entries that named the
  licence say GPLv3 now. Dev docs that recorded the Apache 2.0 decision keep
  it as history, with the date of the change.
- **Fresh history.** The new repository starts from one commit holding the
  1.0.0 (build 2) source. Docs no longer name the old work branches, pull
  requests or commits, which do not exist in this history.
- **Private information removed.** No Apple Developer team ID, bundle-ID
  prefix other than the `com.example.xgrc` placeholder, signing identity,
  certificate, provisioning profile, device name, UDID, personal path or
  email is in the tree. People are not named in the docs. A link to a private
  design canvas was removed from `Design/AppIcon/README.md`. The App Store
  screenshots carry no location or camera metadata (their EXIF holds only
  pixel size and colour space).
- **`.gitignore`** now also keeps out certificates and keys (`*.p12`, `*.p8`,
  `*.cer`, `*.mobileprovision`), Xcode per-user state, archives, `.xcresult`
  bundles, videos, `.env` files and macOS clutter, besides
  `Config/Local.xcconfig`, the generated `.xcodeproj` and build output.

## Building locally

Signing values live only in `Config/Local.xcconfig`, which git ignores; the
format is in `Config/Signing.xcconfig`. Create it, run `xcodegen generate`,
then build in Xcode, as the README's *Build and run* section says. Nothing
from that file, the generated project or `xcuserdata` should be committed.

## Before each push

Search the tree for a team ID, home-folder paths, email addresses and signing
settings before committing, and keep `Config/Signing.xcconfig` at its
placeholders.
