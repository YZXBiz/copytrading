import DesktopCore
import SwiftUI
import UniformTypeIdentifiers

/// The one place CopyTrading is set up, top to bottom: Discord, the interpreter, broker accounts,
/// gurus, and alerts, each a numbered step that turns green when it is done, then one Start
/// Copying. Services open a frosted panel that grows out of their row; accounts and gurus open
/// their editor. People and Accounts only show what this page set up.
struct ConnectionsView: View {
    @Bindable var model: AppModel
    @State private var panel: ConnectionPanelRoute?
    /// Every interpreter service, listed in place under the popular ones.
    @State private var showsAllServices = false
    /// The interpreter as it was before a service's own row was picked, and as picking it left it,
    /// so a sheet closed without typing anything leaves the interpreter as it was.
    @State private var beforeConnect: (draft: ConnectionsDraft, picked: Int)?
    @AppStorage("connections.ideasHidden") private var ideasHidden = false
    /// A channel ID is in and typing has paused for a moment; the setup tour moves on from it.
    @State private var channelsEntered = false
    /// The open panel for Import Setup…, the only way a setup file reaches the app.
    @State private var isImporting = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.42, extraBounce: 0.04) }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 30)
                    step(1, .discord) { section(.discord) }
                        .id(SetupTourTarget.discordRow)
                    step(2, .interpreter) { section(.interpreter) }
                        .id(SetupTourTarget.interpreterServices)
                    SetupStepSection(
                        number: 3, isDone: progress.isDone(.account), title: L10n.string("Broker accounts"),
                        subtitle: L10n.string("Where orders go. Start with paper: pretend money at real prices.")
                    ) { BrokerAccountsRows(model: model).setupTourTarget(.accounts) }
                    .padding(.bottom, 36)
                    .id(SetupTourTarget.accounts)
                    SetupStepSection(
                        number: 4, isDone: progress.isDone(.guru), title: L10n.string("Gurus"),
                        subtitle: L10n.string("Who you copy, and the account each one copies into.")
                    ) { GuruRows(model: model).setupTourTarget(.gurus) }
                    .padding(.bottom, 36)
                    .id(SetupTourTarget.gurus)
                    SetupStepSection(
                        number: 5, isDone: model.setupDraft.notificationsEnabled, isOptional: true,
                        title: ConnectionKind.alerts.title, subtitle: ConnectionKind.alerts.explanation
                    ) { section(.alerts) }
                    .padding(.bottom, 36)
                    if model.hasSetupToStart {
                        ConnectionsStartCard(model: model)
                            .id(SetupTourTarget.startCopying)
                            .padding(.bottom, 36)
                            .transition(.opacity)
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
                            ConnectionPanelContent(
                                page: panel.page, model: model, close: close, cancel: cancel, connecting: isEditingFromProviderRow
                            )
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
            .overlayPreferenceValue(SetupTourTargetKey.self) { targets in
                // An account or guru sheet covers the page, and a check or start already answers
                // the last stop; the tour waits behind them.
                if let tourStop, model.setupEditor == nil, !model.isValidatingTrading, !model.isActivatingTrading {
                    SetupTourOverlay(stop: tourStop, targets: targets, model: model)
                }
            }
            .task(id: model.setupDraft.channels) {
                channelsEntered = false
                guard !model.setupDraft.sourceChannelIDs.isEmpty else { return }
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                channelsEntered = true
            }
            .onChange(of: tourStop, initial: true) { _, stop in
                model.setupTourStop = stop
                guard model.isTouringSetup else { return }
                guard let stop else { return model.endSetupTour() }
                // Stops inside a panel are already in view; the page scrolls to the others.
                guard panel == nil else { return }
                withAnimation(motion) { scroller.scrollTo(stop.target, anchor: .center) }
            }
        }
        .padding([.trailing, .bottom], 8)
        .onChange(of: model.requestedConnection, initial: true) { _, kind in
            guard let kind else { return }
            model.requestedConnection = nil
            open(.editor(kind), from: .section(kind))
        }
        .animation(motion, value: model.hasSetupToStart)
        .navigationTitle(L10n.string("Connections"))
    }

    private var progress: SetupProgress { model.setupProgress }

    /// Where the setup tour points while it runs.
    /// Nil once the setup is done; the tour then ends. An account or guru sheet only hides it.
    private var tourStop: SetupTourStop? {
        guard model.isTouringSetup else { return nil }
        let open: ConnectionKind? = if case .editor(let kind) = panel?.page { kind } else { nil }
        return SetupTourStop.current(progress: progress, channelsEntered: channelsEntered, panel: open)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Connections"))
                    .font(DesignTokens.pageTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.string("Set up CopyTrading here, top to bottom. Nothing is saved or traded until you start copying."))
                    .font(.body)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if model.savedTradingConfiguration == nil {
                Button(L10n.string("Import Setup…"), systemImage: "square.and.arrow.down") { isImporting = true }
                    .controlSize(.small)
                    .help(L10n.string("Fill every field from a text file with your keys. Nothing is saved until it's checked."))
                    .accessibilityIdentifier("connections.importSetup")
            }
            Menu {
                Button(L10n.string("Import Setup…"), systemImage: "square.and.arrow.down") { isImporting = true }
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
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.plainText, .text, .json]) { result in
            if case .success(let url) = result { model.importSetup(from: url) }
        }
    }

    /// A service's step, numbered in setup order.
    private func step(_ number: Int, _ kind: ConnectionKind, @ViewBuilder rows: () -> some View) -> some View {
        SetupStepSection(
            number: number, isDone: progress.isDone(kind == .discord ? .discord : .interpreter), title: kind.title,
            subtitle: kind.explanation, content: rows
        )
        .padding(.bottom, 36)
    }

    @ViewBuilder
    private func section(_ kind: ConnectionKind) -> some View {
        let summary = ConnectionSummary.of(kind, in: model)
        VStack(alignment: .leading, spacing: 10) {
            SettingsSection(dividerInset: 56) {
                switch kind {
                case .discord:
                    serviceRow(
                        kind, brand: "discord", summary: summary, title: L10n.string("Discord token and channels")
                    )
                    .setupTourTarget(.discordRow)
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
            .setupTourTarget(kind == .interpreter ? .interpreterServices : nil)
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
            .onTapGesture(perform: cancel)
            .accessibilityHidden(true)
    }

    /// Picks an interpreter service from its own row and opens its settings out of that row.
    private func connect(_ provider: TradingProviderName) {
        let before = model.setupDraft
        model.setupDraft.provider = provider
        model.setupDraft.suggestModel(after: before.provider)
        beforeConnect = (before, interpreterFingerprint)
        showsAllServices = false
        open(.editor(.interpreter), from: .provider(provider))
    }

    private func open(_ page: ConnectionPanelPage, from origin: ConnectionPanelOrigin) {
        withAnimation(motion) {
            panel = ConnectionPanelRoute(page: page, origin: origin)
        }
    }

    /// Closing a service picked from its own row before typing anything puts back the one in use.
    private func cancel() {
        if let before = beforeConnect?.draft, interpreterFingerprint == beforeConnect?.picked {
            model.setupDraft.provider = before.provider
            model.setupDraft.modelName = before.modelName
            model.setupDraft.providerBaseURL = before.providerBaseURL
            model.setupDraft.providerAPIKey = before.providerAPIKey
        }
        close()
    }

    /// Everything the interpreter sheet edits, digested so a typed key is never held twice.
    private var interpreterFingerprint: Int {
        let draft = model.setupDraft
        var hasher = Hasher()
        hasher.combine(draft.provider)
        hasher.combine(draft.modelName)
        hasher.combine(draft.providerBaseURL)
        hasher.combine(draft.providerAPIKey)
        return hasher.finalize()
    }

    /// Alerts are on once a chat or a bot token is in, so an offer closed untouched leaves them off.
    private func close() {
        beforeConnect = nil
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
