#if canImport(XCTest)
    import Foundation
    import XCTest
    @testable import AppLocalizationCore

    final class AppLocalizationTests: XCTestCase {
        @MainActor
        func testLanguageChoicePersistsAndUnknownStoredLanguageDefaultsToEnglish() {
            let suite = "AppLocalizationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }

            let preference = AppLanguagePreference(defaults: defaults)
            XCTAssertEqual(preference.language, .english)

            preference.select(.simplifiedChinese)
            XCTAssertEqual(
                defaults.string(forKey: AppLanguagePreference.storageKey),
                AppLanguage.simplifiedChinese.rawValue
            )
            XCTAssertEqual(AppLanguagePreference(defaults: defaults).language, .simplifiedChinese)

            defaults.set("fr", forKey: AppLanguagePreference.storageKey)
            XCTAssertEqual(AppLanguagePreference(defaults: defaults).language, .english)
        }

        @MainActor
        func testLocalizedLookupUsesCurrentChoiceAndFormatsArguments() {
            let preference = AppLanguagePreference.shared
            let original = preference.language
            defer { preference.select(original) }

            preference.select(.english)
            XCTAssertEqual(L10n.string("Language"), "Language")
            preference.select(.simplifiedChinese)
            XCTAssertEqual(L10n.string("Language"), "语言")
            XCTAssertEqual(L10n.string("简体中文"), "简体中文")
            XCTAssertEqual(
                L10n.string("Connected to %@ and %@", "feed", "broker"),
                "Connected to feed and broker"
            )
        }

        @MainActor
        func testTheAssistantSpeaksTheOwnersTerms() {
            let preference = AppLanguagePreference.shared
            let original = preference.language
            defer { preference.select(original) }

            preference.select(.english)
            XCTAssertEqual(L10n.string("Review the approval…"), "Review…")
            preference.select(.simplifiedChinese)
            XCTAssertEqual(L10n.string("Review the approval…"), "去审批…")
            XCTAssertEqual(L10n.string("Ask the Assistant"), "询问助手")
            XCTAssertEqual(L10n.string("The assistant is asking for approval"), "助手请求批准")
            XCTAssertEqual(L10n.string("How did %@ do this week?", "Zhao"), "Zhao 这周表现怎么样？")
            XCTAssertTrue(L10n.string("How did my gurus do this week?").contains("信号源"))
            XCTAssertTrue(L10n.string("What's in my paper account?").contains("模拟盘"))
            XCTAssertTrue(L10n.string("Set up a model in Connections first").contains("AI 模型"))
        }

        func testMissingChineseEntryFallsBackToEnglishCatalogValue() {
            XCTAssertEqual(
                L10n.localizedString(
                    key: "Fixture fallback key",
                    language: .simplifiedChinese,
                    resourceBundle: .module
                ),
                "English fixture translation"
            )
        }

        func testMissingCatalogEntryFallsBackToItsEnglishSourceText() {
            let source = "Uncatalogued source phrase"
            XCTAssertEqual(
                L10n.localizedString(
                    key: source,
                    language: .simplifiedChinese,
                    resourceBundle: .module
                ),
                source
            )
        }
    }
#endif
