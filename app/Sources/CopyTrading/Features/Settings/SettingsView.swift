import DesktopCore
import SwiftUI

/// Settings as a light panel with close and back at the top, the page's
/// title, and its groups of rows. The pages are listed in the Settings sidebar.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
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
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.settingsPage)
        .background(Palette.panel)
        .clipShape(.rect(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline, lineWidth: 1 / displayScale)
        }
        .padding([.trailing, .bottom], 8)
        .navigationTitle(L10n.string("Settings"))
    }

    private var header: some View {
        HStack(spacing: 10) {
            SquareHeaderButton(title: L10n.string("Close Settings"), symbol: "xmark", fill: Palette.well, action: model.closeSettings)
                // While the assistant is open, Esc closes it first.
                .keyboardShortcut(model.assistant.isOpen ? nil : .cancelAction)
                .accessibilityIdentifier("settings.close")
            if !model.settingsTrail.isEmpty {
                SquareHeaderButton(title: L10n.string("Back"), symbol: "chevron.left", fill: Palette.well, action: model.settingsBack)
                    .accessibilityIdentifier("settings.back")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            Text(L10n.string(model.settingsPage.title))
                .font(DesignTokens.pageTitle)
                .foregroundStyle(Palette.ink)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
                .contentTransition(.opacity)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.settingsTrail.isEmpty)
    }

    @ViewBuilder
    private var page: some View {
        switch model.settingsPage {
        case .general: GeneralSettingsPage(model: model)
        case .appearance: AppearanceSettingsPage()
        case .updates: UpdatesSettingsPage(model: model)
        case .engine: EngineSettingsPage(model: model)
        case .agents: AgentAccessPage(model: model)
        case .backups: BackupsSettingsPage(model: model)
        case .logs: LogsSettingsPage(model: model)
        }
    }
}
