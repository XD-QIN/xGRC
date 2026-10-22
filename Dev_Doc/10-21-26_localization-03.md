# Localization

xGRC ships the same thirteen languages as xMosaique: English, Chinese
(Simplified `zh-Hans`, Traditional `zh-Hant`), Spanish (Spain `es`, Latin
America `es-419`), Portuguese (Brazil `pt-BR`), French `fr`, German `de`,
Italian `it`, Japanese `ja`, Korean `ko`, Hindi `hi` and Indonesian `id`.
Every translation is a machine draft until a native speaker has read it.

## Settings › Language

- **English by default**, whatever the device's language (the maintainer's
  decision, 2026-10-21; xMosaique follows the device instead). The choice is
  per device: iPhone and iPad in Settings › Language (a list, each language in
  its own name), the watch in Settings › Language (tap, then the Digital
  Crown).
- **It applies at once.** `AppLanguage` (`Apps/Shared/Localization`) keeps the
  choice in the App Group's defaults, so the widgets, the Live Activity and
  the controls read it too, and:
  - `Bundle.main` answers `Text` and other bundle lookups from the chosen
    language's `.lproj` (`LanguageBundle`);
  - `String(localized:)` in the app resolves to an overload declared next to
    it that binds the chosen locale. Foundation's own looks up the device's
    language for the rest of the launch, so without it those strings would
    change only after a restart;
  - the root view gets the language's locale and is rebuilt, so dates,
    numbers and relative times follow.
- **System-drawn text** (the Bluetooth and Location permission prompts, Siri
  phrases) follows `AppleLanguages`, which is set at the same time and takes
  effect the next time xGRC starts. The footer under the list says so.

## Where the strings are

| Catalog | Targets | Holds |
|---|---|---|
| `Apps/Shared/Localization/Localizable.xcstrings` | all four | every UI string, including the package strings below |
| `Apps/xGRC-iOS/InfoPlist.xcstrings` | iPhone and iPad app | permission prompts |
| `Apps/xGRC-watchOS/InfoPlist.xcstrings` | watch app | permission prompts |
| `Apps/Shared/App/AppShortcuts.xcstrings` | iPhone and watch apps | Siri phrases |

The packages are not localized themselves. DesignKit's labels are
`LocalizedStringResource`s and `Text("…")` keys, which look in the app's
bundle; SessionKit's few user-facing reasons go through
`localizedFromCatalog`. Their keys are in `Localizable.xcstrings` by hand
(`extractionState: manual`), so a change to one of those English strings in a
package must be made in the catalog too.

## Adding or changing a string

1. Write it as `Text("…")`, a `LocalizedStringKey` parameter, or
   `String(localized: "…")`. A plain `String` literal shown on screen is not
   translated.
2. Run `xcodebuild -exportLocalizations -project xGRC.xcodeproj
   -localizationPath /tmp/l10n -exportLanguage en`; it adds new keys to the
   catalogs.
3. Translate the new keys for all twelve languages (`state: translated`), or
   leave them `new`: an untranslated key shows in English.

Keep `%@` / `%lld` specifiers, `${applicationName}` in Siri phrases, glyphs
(`◐ ✓ ↑ ·`) and brand and camera-menu names as they are.

## The App Store listing

`App_Store_Intro/appstore_intro_<X>.md`, one file per language as in
xMosaique (Chinese and Spanish carry two localizations each). Review notes,
privacy answers and TestFlight text stay in English.

## Not translated

Screenshots (`AppStorePreview/`) are English only, as xMosaique's are. The
`-StoreScreens` mode takes `-xgrc.language <code>` for a localized set later.
