import DesktopCore
import SwiftUI

/// The unlocked workspace: sidebar, the selected screen, and the controls every screen shares.
struct MainSplitView: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    @State private var showsSidebar = true
    @State private var sidebarToggleHovered = false
    @State private var previousScreens: [AppModel.Screen] = []
    @State private var nextScreens: [AppModel.Screen] = []
    @State private var isHistoryNavigation = false
    /// Lock asks first when it would drop setup changes that aren't saved yet.
    @State private var confirmsLock = false
    /// Activity's filter and selection, here so the assistant knows which post "this post" is.
    @State private var activityState = ActivityScreenState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Refresh at once when copying starts, stops, or handles another post; otherwise every 15 s.
    private var refreshTrigger: String {
        let status = model.tradingStatus
        return "\(status?.state.rawValue ?? "none"):\(status?.processedSignals ?? -1):\(model.runtimeState.rawValue)"
    }

    var body: some View {
        content.environment(model.skippedCalls)
    }

    private var content: some View {
        HStack(spacing: 0) {
            if showsSidebar {
                ZStack {
                    // Settings brings its own sidebar.
                    if isShowingSettings {
                        SettingsSidebar(model: model) { sidebarHeader }
                            .transition(.opacity)
                    } else {
                        SidebarView(model: model, accountFeature: accountFeature) { sidebarHeader }
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isShowingSettings)
                .frame(width: 252)
                .padding(8)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                workspaceToolbar
                UpdateAvailableBanner(model: model)
                EngineStoppedBanner(model: model)
                StatusBanner(model: model)
                ScreenDetailView(model: model, accountFeature: accountFeature, activityState: activityState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollEdgeEffectHidden(true, for: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            // Over the page, below the toolbar, inset like the Connections and Settings panels.
            if model.assistant.isOpen {
                AssistantPanel(model: model, accountFeature: accountFeature, activityState: activityState)
                    .padding(.top, 52)
                    .padding([.trailing, .bottom], 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.34), value: model.assistant.isOpen)
        .background(Palette.canvas)
        // Seat the window buttons inside the sidebar panel, level with its header row
        // (panel inset 8 + half the 40-point header); without the sidebar, level with the toolbar.
        .background(WindowButtonPlacement(leading: 20, centerY: showsSidebar ? 28 : 26))
        .ignoresSafeArea(.container)
        .tint(Palette.accent)
        .sheet(item: pendingAgentProposal) { proposal in
            AgentProposalSheet(model: model, proposal: proposal)
        }
        .environment(\.postProgressContext, progressContext)
        .task(id: refreshTrigger) {
            await liveRefresh()
        }
        .task(id: model.tradingStatus?.state) {
            await model.startCopyingOnLaunchIfWanted()
        }
        .onChange(of: model.selectedScreen) { old, new in
            if new == .settings, old != .settings {
                model.screenBeforeSettings = old
                model.settingsTrail.removeAll()
            }
            if isHistoryNavigation {
                isHistoryNavigation = false
            } else {
                previousScreens.append(old)
                nextScreens.removeAll()
            }
        }
    }

    private var isShowingSettings: Bool { model.selectedScreen == .settings }

    private var sidebarHeader: some View {
        HStack {
            Spacer()
            sidebarToggle
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 12) {
            if !showsSidebar {
                sidebarToggle
            }
            navigationHistory
            if !showsSidebar {
                pageMenu
            }
            Spacer(minLength: 12)
            ToolbarStatus(model: model, accountFeature: accountFeature)
            CopyingControl(model: model)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            AssistantToolbarButton(assistant: model.assistant)
            Button(L10n.string("Lock"), systemImage: "lock", action: requestLock)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help(
                    L10n.string(
                        model.hasUnsavedSetupChanges ? "Lock CopyTrading. Unsaved setup changes are discarded." : "Lock CopyTrading")
                )
                .confirmationDialog(
                    L10n.string("Lock and discard your unsaved setup changes?"), isPresented: $confirmsLock, titleVisibility: .visible
                ) {
                    Button(L10n.string("Discard and Lock"), role: .destructive, action: lock)
                    Button(L10n.string("Cancel"), role: .cancel) {}
                } message: {
                    Text(L10n.string("What you typed in Connections is dropped, keys included. Your saved setup stays."))
                }
        }
        // Reserve the window buttons (seated 20 points in) when the sidebar is collapsed.
        .padding(.leading, showsSidebar ? 0 : 80)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .controlSize(.large)
    }

    private var navigationHistory: some View {
        HStack(spacing: 2) {
            Button(L10n.string("Back"), systemImage: "chevron.left", action: goBack)
                .frame(width: 28, height: 32)
                .disabled(previousScreens.isEmpty)
                .keyboardShortcut("[", modifiers: .command)
                .help(L10n.string("Back"))
                .accessibilityIdentifier("toolbar.back")
            Button(L10n.string("Forward"), systemImage: "chevron.right", action: goForward)
                .frame(width: 28, height: 32)
                .disabled(nextScreens.isEmpty)
                .keyboardShortcut("]", modifiers: .command)
                .help(L10n.string("Forward"))
                .accessibilityIdentifier("toolbar.forward")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(QuietPressButtonStyle())
        .foregroundStyle(Palette.secondaryInk)
    }

    /// When the sidebar is hidden, its destinations remain one click away: the screens, or in
    /// Settings, its pages.
    private var pageMenu: some View {
        Menu {
            if isShowingSettings {
                ForEach(SettingsPageGroup.allCases) { group in
                    Section(L10n.string(group.title)) {
                        ForEach(group.pages) { page in
                            Button(L10n.string(page.title), systemImage: page == model.settingsPage ? "checkmark" : page.symbol) {
                                model.show(page)
                            }
                        }
                    }
                }
                Divider()
                Button(L10n.string("Close Settings"), systemImage: "xmark", action: model.closeSettings)
            } else {
                screenMenuItems
            }
        } label: {
            Label(
                isShowingSettings ? L10n.string(model.settingsPage.title) : model.title(of: model.selectedScreen),
                systemImage: isShowingSettings ? model.settingsPage.symbol : model.selectedScreen.symbol
            )
            .labelStyle(.titleAndIcon)
            .font(DesignTokens.bodyEmphasis)
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(Palette.ink)
        .fixedSize()
        .help(L10n.string("Navigate to a page"))
        .accessibilityIdentifier("toolbar.pages")
    }

    private var screenMenuItems: some View {
        ForEach(model.navigableScreens, id: \.self) { screen in
            Button(model.title(of: screen), systemImage: screen == model.selectedScreen ? "checkmark" : screen.symbol) {
                model.selectedScreen = screen
            }
        }
    }

    private func goBack() {
        guard let screen = previousScreens.popLast() else { return }
        nextScreens.append(model.selectedScreen)
        isHistoryNavigation = true
        model.selectedScreen = screen
    }

    private func goForward() {
        guard let screen = nextScreens.popLast() else { return }
        previousScreens.append(model.selectedScreen)
        isHistoryNavigation = true
        model.selectedScreen = screen
    }

    private var sidebarToggle: some View {
        Button(showsSidebar ? L10n.string("Hide Sidebar") : L10n.string("Show Sidebar"), systemImage: "sidebar.left") {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                showsSidebar.toggle()
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(QuietPressButtonStyle())
        .font(.system(size: 17))
        .foregroundStyle(Palette.secondaryInk)
        .frame(width: 32, height: 32)
        .background(sidebarToggleHovered ? Palette.hover : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { sidebarToggleHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: sidebarToggleHovered)
        .help(showsSidebar ? L10n.string("Hide Sidebar") : L10n.string("Show Sidebar"))
        .keyboardShortcut("s", modifiers: [.command, .control])
        .accessibilityIdentifier("toolbar.sidebar")
    }

    /// Shows the oldest waiting request until the owner approves or rejects it.
    private var pendingAgentProposal: Binding<AgentProposal?> {
        Binding(get: { model.pendingAgentProposal }, set: { _ in })
    }

    /// The saved setup's reader and order timeouts, for each post's live step.
    private var progressContext: PostProgress.Context {
        let setup = model.savedTradingConfiguration
        return PostProgress.Context(
            readerModel: setup?.provider.model,
            orderTimeouts: Dictionary(
                (setup?.accounts ?? []).map { ($0.id, TimeInterval($0.policy.orderTimeoutSeconds)) },
                uniquingKeysWith: { first, _ in first }))
    }

    /// Everything every 15 s; while a post is in flight, its newest posts every second between.
    private func liveRefresh() async {
        var lastFull = Date.distantPast
        while !Task.isCancelled {
            if Date.now.timeIntervalSince(lastFull) >= ActivityRefreshCadence.settled {
                await accountFeature.refresh(using: model.accountActions())
                await accountFeature.refreshHistories(using: model.accountActions())
                lastFull = .now
            } else {
                await accountFeature.refreshActivity(using: model.accountActions())
            }
            do {
                try await Task.sleep(for: .seconds(ActivityRefreshCadence.interval(for: accountFeature.activity)))
            } catch {
                return
            }
        }
    }

    private func requestLock() {
        if model.hasUnsavedSetupChanges {
            confirmsLock = true
        } else {
            lock()
        }
    }

    private func lock() {
        Task { await model.lockAccess() }
    }
}
