import DesktopCore
import SwiftUI

/// The outside services CopyTrading talks to: one
/// section per service on the app's chart paper, a tile once it is connected, and a frosted panel
/// that grows out of the card you click. Gurus live in People and broker accounts in Accounts.
struct ConnectionsView: View {
    @Bindable var model: AppModel
    @State private var panel: ConnectionPanelRoute?
    @State private var hovered: ConnectionPanelOrigin?
    @AppStorage("connections.ideasHidden") private var ideasHidden = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.42, extraBounce: 0.04) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 44)
                ForEach(ConnectionKind.allCases) { kind in
                    section(kind)
                        .padding(.bottom, 52)
                }
                if !ideasHidden {
                    ConnectionIdeasSection(provider: model.setupDraft.provider, hide: hideIdeas)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 14)
            .padding(.bottom, 44)
            .frame(maxWidth: 1_080, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .background { ChartPaperBackdrop(focus: UnitPoint(x: 0.75, y: 0.04)) }
        .overlayPreferenceValue(ConnectionOriginKey.self) { origins in
            GeometryReader { layer in
                ZStack {
                    if let panel {
                        veil
                            .transition(.opacity)
                        ConnectionPanelContent(
                            page: panel.page, model: model, choose: show, chooseProvider: chooseProvider, close: close
                        )
                        .overlay(alignment: .topTrailing) { closeButton }
                        .transition(
                            ConnectionPanelTransition(
                                origin: origins[panel.origin].map { layer[$0] }, layer: layer.size, reduceMotion: reduceMotion))
                    }
                }
                .frame(width: layer.size.width, height: layer.size.height)
            }
        }
        .clipShape(.rect(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous))
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
            SquareHeaderButton(title: L10n.string("New Connection"), symbol: "plus.circle.fill") {
                open(.catalog, from: .newConnection)
            }
            .anchorPreference(key: ConnectionOriginKey.self, value: .bounds) { [.newConnection: $0] }
            .accessibilityIdentifier("connections.new")
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
        VStack(alignment: .leading, spacing: 20) {
            ConnectionsSectionHeader(
                title: kind.sectionTitle,
                subtitle: summary == nil ? nil : kind.purpose,
                addTitle: kind == .discord && summary != nil ? "Add a Channel" : nil,
                add: { open(.editor(kind), from: .section(kind)) }
            )
            Button {
                open(kind)
            } label: {
                if let summary {
                    ConnectionTile(summary: summary, isHovered: hovered == .section(kind))
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    ConnectionAddCard(title: kind.addTitle, subtitle: kind.purpose, isHovered: hovered == .section(kind))
                        .transition(.opacity)
                }
            }
            .buttonStyle(QuietPressButtonStyle())
            .onHover { inside in
                if inside {
                    hovered = .section(kind)
                } else if hovered == .section(kind) {
                    hovered = nil
                }
            }
            .anchorPreference(key: ConnectionOriginKey.self, value: .bounds) { [.section(kind): $0] }
            // The label replaces the card's words; the element stays the button, so it can be pressed.
            .accessibilityLabel(summary.map { L10n.string("%@, %@, %@", $0.title, $0.detail, $0.status.text) } ?? kind.addTitle)
            .accessibilityHint(kind.purpose)
            .accessibilityIdentifier("connections.\(kind.rawValue)")
            .animation(motion, value: summary == nil)
        }
    }

    /// The page dims to a light veil under an open panel; clicking it closes the panel.
    private var veil: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.black.opacity(0.32) : Color.white.opacity(0.38))
            .contentShape(.rect)
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button(L10n.string("Close"), systemImage: "xmark", action: close)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.tertiaryInk)
            .frame(width: 26, height: 26)
            .background(Palette.page.opacity(0.6), in: .circle)
            .padding(14)
            // While the assistant is open, Esc closes it first.
            .keyboardShortcut(model.assistant.isOpen ? nil : .cancelAction)
            .help(L10n.string("Close"))
            .accessibilityIdentifier("connections.close")
    }

    /// An empty section asks first, as the picker does: which interpreter, or straight to
    /// Discord's and Telegram's settings. A connected section opens its settings.
    private func open(_ kind: ConnectionKind) {
        let connected = ConnectionSummary.of(kind, in: model) != nil
        switch kind {
        case .interpreter where !connected:
            open(.interpreters, from: .section(kind))
        default:
            open(.editor(kind), from: .section(kind))
        }
    }

    private func open(_ page: ConnectionPanelPage, from origin: ConnectionPanelOrigin) {
        withAnimation(motion) {
            panel = ConnectionPanelRoute(page: page, origin: origin)
        }
    }

    private func show(_ page: ConnectionPanelPage) {
        withAnimation(motion) {
            panel?.page = page
        }
    }

    private func chooseProvider(_ provider: TradingProviderName) {
        let previous = model.setupDraft.provider
        model.setupDraft.provider = provider
        model.setupDraft.suggestModel(after: previous)
        show(.editor(.interpreter))
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
