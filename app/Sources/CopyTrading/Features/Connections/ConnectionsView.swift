import DesktopCore
import SwiftUI

/// The outside services CopyTrading talks to, on the same quiet panel as Settings: one section per
/// service, each a list of rows with the service's logo and one action, and a frosted panel that
/// grows out of the row you click. Gurus live in People and broker accounts in Accounts.
struct ConnectionsView: View {
    @Bindable var model: AppModel
    @State private var panel: ConnectionPanelRoute?
    /// Every interpreter service, listed in place under the popular ones.
    @State private var showsAllServices = false
    @AppStorage("connections.ideasHidden") private var ideasHidden = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.42, extraBounce: 0.04) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 30)
                ForEach(ConnectionKind.allCases) { kind in
                    section(kind)
                        .padding(.bottom, 36)
                }
                if !ideasHidden {
                    ConnectionIdeasSection(provider: model.setupDraft.provider, hide: hideIdeas)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 14)
            .padding(.bottom, 44)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .background(Palette.panel)
        .overlayPreferenceValue(ConnectionOriginKey.self) { origins in
            GeometryReader { layer in
                ZStack {
                    if let panel {
                        veil
                            .transition(.opacity)
                        ConnectionPanelContent(page: panel.page, model: model, close: close)
                            .transition(
                                ConnectionPanelTransition(
                                    origin: origins[panel.origin].map { layer[$0] }, layer: layer.size, reduceMotion: reduceMotion))
                    }
                }
                .frame(width: layer.size.width, height: layer.size.height)
            }
        }
        .clipShape(.rect(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline, lineWidth: 1 / displayScale)
        }
        .padding([.trailing, .bottom], 8)
        .onChange(of: model.requestedConnection, initial: true) { _, kind in
            guard let kind else { return }
            model.requestedConnection = nil
            open(.editor(kind), from: .section(kind))
        }
        .navigationTitle(L10n.string("Connections"))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Connections"))
                .font(DesignTokens.pageTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Menu {
                Button(L10n.string(ideasHidden ? "Show Ideas" : "Hide Ideas"), systemImage: "lightbulb", action: toggleIdeas)
                Button(L10n.string("Open Getting Started"), systemImage: "hand.wave") { model.selectedScreen = .gettingStarted }
            } label: {
                SquareControlLabel(symbol: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.string("More"))
            .accessibilityLabel(L10n.string("More"))
        }
    }

    @ViewBuilder
    private func section(_ kind: ConnectionKind) -> some View {
        let summary = ConnectionSummary.of(kind, in: model)
        VStack(alignment: .leading, spacing: 10) {
            SettingsSection(title: kind.title, subtitle: kind.explanation, dividerInset: 56) {
                switch kind {
                case .discord:
                    serviceRow(
                        kind, brand: "discord", summary: summary, title: L10n.string("Discord token and channels"))
                case .alerts:
                    if let summary {
                        serviceRow(kind, brand: model.setupDraft.notificationService.brandIcon, summary: summary, title: summary.title)
                    }
                    ForEach(TradingAlertService.allCases, id: \.self) { service in
                        if summary == nil || service != model.setupDraft.notificationService {
                            alertRow(service, switching: summary != nil)
                        }
                    }
                case .interpreter:
                    if let summary, !isEditingFromProviderRow {
                        serviceRow(kind, brand: model.setupDraft.provider.brandIcon, summary: summary, title: summary.title)
                        moreServicesRow(title: L10n.string("Use another service"), detail: nil)
                        if showsAllServices {
                            ForEach(otherServices, id: \.self) { provider in
                                providerRow(provider, title: L10n.string(provider.title), detail: provider.tagline, action: "Switch")
                            }
                        }
                    } else {
                        ForEach(ProviderGroup.popular.providers, id: \.self) { provider in
                            providerRow(provider, title: L10n.string("%@ API key", L10n.string(provider.title)), detail: nil)
                        }
                        if showsAllServices {
                            ForEach(ProviderGroup.more.providers, id: \.self) { provider in
                                providerRow(
                                    provider, title: L10n.string("%@ API key", L10n.string(provider.title)), detail: provider.tagline)
                            }
                        }
                        moreServicesRow(
                            title: L10n.string(showsAllServices ? "Fewer services" : "More services"),
                            detail: showsAllServices
                                ? nil : L10n.string("%@, and more", Humanize.joined(["OpenRouter", "Groq", "xAI", "Mistral"])))
                    }
                }
            }
            if kind == .interpreter && (summary == nil || isEditingFromProviderRow) {
                SettingsSection(dividerInset: 56) {
                    ForEach(ProviderGroup.ownModel.providers, id: \.self) { provider in
                        providerRow(provider, title: L10n.string(provider.title), detail: provider.tagline)
                    }
                }
            }
        }
        .animation(motion, value: summary == nil)
    }

    /// A service with its own editor: "Connect" before it is set up, its setting and status after.
    private func serviceRow(
        _ kind: ConnectionKind, brand: String?, summary: ConnectionSummary?, title: String
    ) -> some View {
        ConnectionServiceRow(
            brand: brand,
            title: summary?.title ?? title,
            detail: summary.map { L10n.string("%@ · %@", $0.detail, $0.status.text) },
            tone: summary?.status.tone,
            action: L10n.string(summary == nil ? "Connect" : "Edit"),
            origin: .section(kind),
            identifier: "connections.\(kind.rawValue)"
        ) { open(.editor(kind), from: .section(kind)) }
    }

    private func providerRow(
        _ provider: TradingProviderName, title: String, detail: String?, action: String = "Connect"
    ) -> some View {
        ConnectionServiceRow(
            brand: provider.brandIcon,
            title: title,
            detail: detail,
            action: L10n.string(action),
            origin: .provider(provider),
            identifier: "connections.provider.\(provider.rawValue)"
        ) { connect(provider) }
    }

    /// Telegram or a Discord channel: Connect before alerts are on, Switch to the other after.
    private func alertRow(_ service: TradingAlertService, switching: Bool) -> some View {
        ConnectionServiceRow(
            brand: service.brandIcon,
            title: L10n.string(service == .discord ? "Discord channel" : "Telegram bot"),
            detail: switching ? nil : L10n.string(service == .discord ? "Through a channel webhook" : "Through a bot you make"),
            action: L10n.string(switching ? "Switch" : "Connect"),
            origin: .alert(service),
            identifier: !switching && service == .telegram ? "connections.alerts" : "connections.alerts.\(service.rawValue)"
        ) {
            if model.setupDraft.notificationService != service {
                model.setupDraft.notificationService = service
                model.setupDraft.notificationToken = ""
            }
            open(.editor(.alerts), from: .alert(service))
        }
    }

    /// Shows or hides every other interpreter service in place, under the ones listed.
    private func moreServicesRow(title: String, detail: String?) -> some View {
        ConnectionServiceRow(
            brand: nil,
            symbol: "square.grid.2x2",
            title: title,
            detail: detail,
            chevron: showsAllServices ? .expanded : .collapsed,
            origin: .section(.interpreter),
            identifier: "connections.interpreter.more"
        ) {
            withAnimation(motion) { showsAllServices.toggle() }
        }
    }

    /// A panel opened from a service's own row keeps that row on the page until it closes: typing
    /// the first character of a model would otherwise swap the list for the connected row, and the
    /// panel would lose the row it grew from, and the keystrokes with it.
    private var isEditingFromProviderRow: Bool {
        if case .provider = panel?.origin { true } else { false }
    }

    /// Every interpreter service but the one in use, popular ones first.
    private var otherServices: [TradingProviderName] {
        ProviderGroup.allCases.flatMap(\.providers).filter { $0 != model.setupDraft.provider }
    }

    /// The page dims to a light veil under an open panel; clicking it closes the panel.
    private var veil: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.black.opacity(0.32) : Color.white.opacity(0.38))
            .contentShape(.rect)
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
    }

    /// Picks an interpreter service from its own row and opens its settings out of that row.
    private func connect(_ provider: TradingProviderName) {
        let previous = model.setupDraft.provider
        model.setupDraft.provider = provider
        model.setupDraft.suggestModel(after: previous)
        showsAllServices = false
        open(.editor(.interpreter), from: .provider(provider))
    }

    private func open(_ page: ConnectionPanelPage, from origin: ConnectionPanelOrigin) {
        withAnimation(motion) {
            panel = ConnectionPanelRoute(page: page, origin: origin)
        }
    }

    /// Alerts are on once a chat or a bot token is in, so an offer closed untouched leaves them off.
    private func close() {
        withAnimation(motion) {
            if case .editor(.alerts) = panel?.page {
                let draft = model.setupDraft
                model.setupDraft.notificationsEnabled = !draft.notificationChatID.trimmed.isEmpty || !draft.notificationToken.isEmpty
            }
            panel = nil
        }
    }

    private func hideIdeas() {
        withAnimation(motion) { ideasHidden = true }
    }

    private func toggleIdeas() {
        withAnimation(motion) { ideasHidden.toggle() }
    }
}

#Preview("Nothing set up") {
    ConnectionsView(model: AppModel())
        .frame(width: 900, height: 820)
}

#Preview("Set up") {
    let model = AppModel()
    model.setupDraft.channels = "1517754775674949742"
    model.setupDraft.discordToken = "preview"
    model.setupDraft.provider = .deepseek
    model.setupDraft.modelName = "deepseek-flash"
    model.setupDraft.providerAPIKey = "preview"
    return ConnectionsView(model: model)
        .frame(width: 900, height: 820)
}
