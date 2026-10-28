# In-app license and commercial-use note

Date: 2026-10-28. Settings › About now shows the GNU GPL v3 and says what it
means for commercial use, on iPhone, iPad and Apple Watch.

## What changed

- **License row.** About lists Version, Privacy Policy, User Agreement,
  Developer, **License** (value "GPLv3"), then GitHub. License opens a screen
  with the full text of the repository's `LICENSE`, in English: the GPL's
  only binding version. The text is split into paragraphs with the hard line
  breaks removed, so it wraps to the screen, and drawn in a lazy stack so the
  watch lays out only what is visible. If the bundled copy were ever missing,
  the screen shows a link to gnu.org instead.
- **Commercial-use note.** Directly below the GitHub link, as the About
  section's footer:

  > xGRC is open source under the GNU GPL v3. You may use it commercially,
  > but if you distribute xGRC or a work based on it, you must license it
  > under GPLv3 and make its complete source code available. xGRC comes with
  > no warranty.

  The README's License section says the same.
- **Bundling.** `project.yml` copies the root `LICENSE` into the iPhone/iPad
  app and the watch app as a resource, so there is one copy of the text in
  the repository. Run `xcodegen generate` before building.
- **Localization.** "License" and the note are in `Localizable.xcstrings` in
  all thirteen languages (machine drafts, like the rest; they need a native
  speaker's review). "GPLv3" and the license text are not translated.
- **Code.** `AboutInfo` (shared) holds the links, the new `sourceLink`
  (GitHub, kept apart so the License row can sit above it), the note and the
  license text; `LicenseView` (shared) draws it. The link titles are now
  computed, so they follow a language change in Settings without a restart;
  before, they kept the language the app started in.

## Device check

Not built here (no Xcode in this environment). On the next device build:

- Settings › About on iPhone, iPad and the watch: the License row shows
  "GPLv3", opens the full text, and the note sits under GitHub.
- The license screen scrolls smoothly on the watch.
- Switch the language in Settings: the link titles, "License" and the note
  change at once.
