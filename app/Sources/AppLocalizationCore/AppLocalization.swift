import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }

    public var displayNameSourceText: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    fileprivate var formatLocale: Locale {
        Locale(identifier: rawValue)
    }
}

@MainActor
@Observable
public final class AppLanguagePreference {
    public static let storageKey = "appLanguage"
    public static let shared = AppLanguagePreference()

    public private(set) var language: AppLanguage

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.string(forKey: Self.storageKey)
        self.language = storedValue.flatMap(AppLanguage.init(rawValue:)) ?? .english

        if defaults.object(forKey: Self.storageKey) != nil,
            storedValue.flatMap(AppLanguage.init(rawValue:)) == nil
        {
            defaults.set(AppLanguage.english.rawValue, forKey: Self.storageKey)
        }
    }

    public func select(_ language: AppLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: Self.storageKey)
    }
}

public enum L10n {
    /// Sentences as one paragraph: English puts a space between them; Chinese, whose full stop
    /// already carries the gap, puts none.
    @MainActor
    public static func sentences(_ sentences: [String]) -> String {
        sentences.joined(separator: AppLanguagePreference.shared.language == .simplifiedChinese ? "" : " ")
    }

    /// A phrase made a sentence, with the full stop of the app's language: "." or "。".
    @MainActor
    public static func sentence(_ phrase: String) -> String {
        phrase + (AppLanguagePreference.shared.language == .simplifiedChinese ? "。" : ".")
    }

    /// Items joined as a list in the app's language, not the Mac's: "A, B and C", "A、B和C".
    @MainActor
    public static func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and).locale(AppLanguagePreference.shared.language.formatLocale))
    }

    @MainActor
    public static func string(_ englishSourceText: String, _ arguments: CVarArg...) -> String {
        let language = AppLanguagePreference.shared.language
        let localized = localizedString(
            key: englishSourceText,
            language: language,
            resourceBundle: Bundle.module
        )
        guard !arguments.isEmpty else { return localized }
        return String(format: localized, locale: language.formatLocale, arguments: arguments)
    }

    static func localizedString(
        key: String,
        language: AppLanguage,
        resourceBundle: Bundle
    ) -> String {
        if let selected = localizedBundle(for: language, in: resourceBundle) {
            let value = selected.localizedString(forKey: key, value: nil, table: "Localizable")
            if value != key {
                return value
            }
        }

        guard let english = localizedBundle(for: .english, in: resourceBundle) else {
            return key
        }
        return english.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    private static func localizedBundle(for language: AppLanguage, in resourceBundle: Bundle) -> Bundle? {
        guard let url = resourceBundle.url(forResource: language.rawValue, withExtension: "lproj") else {
            return nil
        }
        return Bundle(path: url.path)
    }
}
