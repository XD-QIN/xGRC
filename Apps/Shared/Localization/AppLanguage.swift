import Foundation
import ObjectiveC

/// The language xGRC shows (Settings › Language): English unless the user
/// picks another, whatever the device's language. The same thirteen as
/// xMosaique. The choice is kept in the App Group, so the widgets, the Live
/// Activity and the controls follow it too.
///
/// It applies at once: `Bundle.main` answers every localized lookup
/// (`String(localized:)`, `Text`) from the chosen language's strings, and
/// the root view is rebuilt. Text the system draws for the app (permission
/// prompts, Siri phrases) follows `AppleLanguages`, which is set alongside
/// and takes effect the next time xGRC starts.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case spanishSpain = "es"
    case spanishLatinAmerica = "es-419"
    case portugueseBrazil = "pt-BR"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case hindi = "hi"
    case indonesian = "id"

    var id: String { rawValue }

    /// Always in its own language, so a reader who cannot read the current
    /// one still finds theirs.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .chineseSimplified: "简体中文"
        case .chineseTraditional: "繁體中文"
        case .spanishSpain: "Español (España)"
        case .spanishLatinAmerica: "Español (Latinoamérica)"
        case .portugueseBrazil: "Português (Brasil)"
        case .french: "Français"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .hindi: "हिन्दी"
        case .indonesian: "Bahasa Indonesia"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    private static let storageKey = "xgrc.language"

    /// The App Group's defaults, so the extensions read the same choice.
    private static var defaults: UserDefaults {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "XGRCAppGroup") as? String, !id.isEmpty,
              let shared = UserDefaults(suiteName: id) else { return .standard }
        return shared
    }

    /// The chosen language; English until one is picked.
    static var current: AppLanguage {
        defaults.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    /// Call once, first, in every app and extension entry point.
    static func activate() {
        LanguageBundle.install()
        apply(current)
    }

    static func select(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: storageKey)
        apply(language)
    }

    private static func apply(_ language: AppLanguage) {
        LanguageBundle.use(language.rawValue)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }
}

/// `Bundle.main`, answering localized strings from one language's `.lproj`.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var strings: Bundle?
    nonisolated(unsafe) private static var installed = false

    static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true
        object_setClass(Bundle.main, LanguageBundle.self)
    }

    /// The language's strings; the English source text when it has none.
    static func use(_ code: String) {
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        lock.lock()
        strings = bundle
        lock.unlock()
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        Self.lock.lock()
        let strings = Self.strings
        Self.lock.unlock()
        guard let strings else { return super.localizedString(forKey: key, value: value, table: tableName) }
        return strings.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension String {
    /// A string that comes from the packages (DesignKit labels, SessionKit
    /// reasons) in the chosen language, when the catalog has it.
    var localizedFromCatalog: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }
}

extension String {
    /// `String(localized:)` in the language chosen in Settings › Language.
    /// Foundation's own looks up the device's language, which the in-app
    /// choice may differ from until xGRC starts again; this one, declared in
    /// the app, is the one every `String(localized:)` here resolves to.
    init(localized value: String.LocalizationValue, table: String? = nil, comment: StaticString? = nil) {
        self.init(localized: LocalizedStringResource(value, table: table, locale: AppLanguage.current.locale,
                                                     bundle: .main, comment: comment))
    }
}

extension LocalizedStringResource {
    /// This resource in the language chosen in Settings › Language. A
    /// resource made in a package carries the device's locale.
    var inAppLanguage: LocalizedStringResource {
        var resource = self
        resource.locale = AppLanguage.current.locale
        return resource
    }
}
