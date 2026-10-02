import DesktopCore
import SwiftUI

/// What an open Connections panel shows for its page: the "Create New" choices, the
/// interpreters grouped by kind, or one service's settings.
struct ConnectionPanelContent: View {
    let page: ConnectionPanelPage
    @Bindable var model: AppModel
    let choose: (ConnectionPanelPage) -> Void
    let chooseProvider: (TradingProviderName) -> Void
    let close: () -> Void

    var body: some View {
        switch page {
        case .catalog:
            ConnectionPanel(lead: L10n.string("Create New"), emphasis: L10n.string("Connection")) {
                VStack(spacing: 2) {
                    ConnectionChoiceRow(
                        title: "Discord", detail: L10n.string("Read the channels your gurus post their calls in"),
                        identifier: "connections.choose.discord"
                    ) { choose(.editor(.discord)) }
                    ConnectionChoiceRow(
                        title: L10n.string("AI Interpreter"),
                        detail: L10n.string("%@, and more", Humanize.joined(["Anthropic", "OpenAI", "Gemini", "DeepSeek"])),
                        identifier: "connections.choose.interpreter"
                    ) { choose(.interpreters) }
                    ConnectionChoiceRow(
                        title: L10n.string("Telegram Alerts"),
                        detail: L10n.string("A message on your phone for every order and problem"),
                        identifier: "connections.choose.alerts"
                    ) { choose(.editor(.alerts)) }
                }
            }
        case .interpreters:
            ConnectionPanel(lead: L10n.string("Choose Your"), emphasis: L10n.string("Interpreter")) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(ProviderGroup.allCases) { group in
                            providerGroup(group)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 26)
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 412)
                .fixedSize(horizontal: false, vertical: true)
                // The last rows fade out, so the list reads as one that goes on.
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 44)
                    }
                }
            }
        case .editor(let kind):
            ConnectionPanel(lead: lead(for: kind), emphasis: emphasis(for: kind)) {
                ConnectionEditor(kind: kind, model: model, done: close)
            }
        }
    }

    private func providerGroup(_ group: ProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(DesignTokens.caption.weight(.semibold))
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(group.providers, id: \.self) { provider in
                ConnectionChoiceRow(
                    title: L10n.string(provider.title), detail: provider.tagline, identifier: "connections.choose.\(provider.rawValue)",
                    compact: true
                ) { chooseProvider(provider) }
            }
        }
    }

    @MainActor private func lead(for kind: ConnectionKind) -> String {
        switch kind {
        case .discord: L10n.string("Read Calls From")
        case .interpreter: L10n.string("Read Posts With")
        case .alerts: L10n.string("Send Alerts To")
        }
    }

    private func emphasis(for kind: ConnectionKind) -> String {
        switch kind {
        case .discord: "Discord"
        case .interpreter: model.setupDraft.provider.shortTitle
        case .alerts: "Telegram"
        }
    }
}
