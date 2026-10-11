import DesktopCore
import SwiftUI

/// Settings as a white page: close and back at the top, the page's title in the display face with
/// its lede, and its groups of rows. The pages are listed in the Settings sidebar.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 34)
                page
                    .id(model.settingsPage)
                    .transition(.opacity)
                    .frame(maxWidth: 880, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.settingsPage)
        .background(Palette.page)
        .navigationTitle(L10n.string("Settings"))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                buttons
            }
            PageHeadline(L10n.string(model.settingsPage.title), lede: L10n.string(model.settingsPage.lede))
                .contentTransition(.opacity)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.settingsTrail.isEmpty)
    }

    @ViewBuilder
    private var buttons: some View {
        roundButton(L10n.string("Close Settings"), symbol: "xmark", action: model.closeSettings)
            // While the assistant is open, Esc closes it first.
            .keyboardShortcut(model.assistant.isOpen ? nil : .cancelAction)
            .accessibilityIdentifier("settings.close")
        if !model.settingsTrail.isEmpty {
            roundButton(L10n.string("Back"), symbol: "chevron.left", action: model.settingsBack)
                .accessibilityIdentifier("settings.back")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    /// A grey round button with one symbol, as the page's quiet controls are.
    private func roundButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(PageButtonStyle(horizontalPadding: 8))
            .help(title)
    }

    @ViewBuilder
    private var page: some View {
        switch model.settingsPage {
        case .general: GeneralSettingsPage(model: model)
        case .appearance: AppearanceSettingsPage()
        case .updates: UpdatesSettingsPage()
        case .engine: EngineSettingsPage(model: model)
        case .agents: AgentAccessPage(model: model)
        case .backups: BackupsSettingsPage(model: model)
        case .logs: LogsSettingsPage(model: model)
        }
    }
}
