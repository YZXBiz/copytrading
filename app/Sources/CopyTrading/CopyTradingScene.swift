import AppLocalizationCore
import SwiftUI

/// The app's window and menu bar extra. It lives in the library, with every screen, so the
/// executable is only an entry point and Xcode can preview the screens.
@MainActor
public struct CopyTradingScene: Scene {
    let lifecycle: AppLifecycleDelegate
    let updater: any AppUpdating
    @State private var model = AppModel.makeForLaunch()
    @State private var languagePreference = AppLanguagePreference.shared
    /// Accounts and activity are shared by the window and the menu bar; both clear on lock.
    @State private var accountFeature = AccountFeatureModel()

    public init(lifecycle: AppLifecycleDelegate, updater: any AppUpdating) {
        self.lifecycle = lifecycle
        self.updater = updater
        TipsSetup.configure()
    }

    public var body: some Scene {
        Window("CopyTrading", id: "main") {
            PlatformRootView(model: model, accountFeature: accountFeature)
                .environment(\.appUpdater, updater)
                .environment(languagePreference)
                .environment(\.locale, Locale(identifier: languagePreference.language.rawValue))
                .environment(\.tipGeneration, model.tipGeneration)
                .frame(minWidth: 980, minHeight: 640)
                .containerBackground(Palette.canvas, for: .window)
                .task {
                    lifecycle.model = model
                    model.startIfNeeded()
                }
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            UpdateCommands(updater: updater)
            SetupCommands(model: model)
            GoCommands(model: model)
            HelpCommands(model: model)
            AssistantCommands(model: model)
        }

        MenuBarExtra {
            MenuBarView(model: model, accountFeature: accountFeature)
                .environment(languagePreference)
                .environment(\.locale, Locale(identifier: languagePreference.language.rawValue))
                .task {
                    lifecycle.model = model
                }
        } label: {
            // The status item drops the title, and the symbol would otherwise be announced as "Divide".
            Label("CopyTrading", systemImage: "arrow.triangle.branch")
                .accessibilityLabel("CopyTrading")
        }
        .menuBarExtraStyle(.window)
    }
}
