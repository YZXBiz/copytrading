import AppLocalizationCore
import Testing

/// VoiceOver reads the Engine page's heading as the word the page shows.
@Test @MainActor func theEngineHeadingSaysTheSameWordToVoiceOver() throws {
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    for language in [AppLanguage.english, .simplifiedChinese] {
        preference.select(language)
        for state in [AppModel.RuntimeState.ready, .starting, .degraded, .stopped, .failed] {
            for needsLook in [false, true] {
                let word = EngineStateWord.word(state, needsLook: needsLook)
                let spoken = EngineStateWord.spoken(state, needsLook: needsLook)
                #expect(spoken.hasSuffix(word), "VoiceOver read \(spoken) while the page showed \(word)")
            }
        }
    }
    preference.select(.english)
    #expect(EngineStateWord.spoken(.ready, needsLook: false) == "Local engine, Running")
}
