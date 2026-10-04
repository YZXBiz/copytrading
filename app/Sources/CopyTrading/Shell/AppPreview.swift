import AppLocalizationCore
import SwiftUI

#if DEBUG
    /// The real workspace in the canvas, with one model shared across every screen.
    /// App launch and its automatic engine startup are deliberately outside this preview.
    @MainActor
    private struct AppPreview: View {
        @State private var model: AppModel
        @State private var accountFeature = AccountFeatureModel()
        @State private var languagePreference = AppLanguagePreference.shared

        init() {
            let model = AppModel()
            model.selectedScreen = .connections
            model.isTradingUnlocked = true
            _model = State(initialValue: model)
        }

        var body: some View {
            MainSplitView(model: model, accountFeature: accountFeature)
                .environment(languagePreference)
                .environment(\.locale, Locale(identifier: languagePreference.language.rawValue))
                .environment(\.tipGeneration, model.tipGeneration)
                .frame(minWidth: 980, minHeight: 640)
        }
    }

    #Preview("Entire app", traits: .fixedLayout(width: 1180, height: 800)) {
        AppPreview()
    }
#endif
