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
    /// Activity's filter and selection, here so the assistant knows which post "this post" is.
    @State private var activityState = ActivityScreenState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Refresh at once when copying starts, stops, or handles another post; otherwise every 15 s.
    private var refreshTrigger: String {
        let status = model.tradingStatus
        return "\(status?.state.rawValue ?? "none"):\(status?.processedSignals ?? -1):\(model.runtimeState.rawValue)"
    }

    var body: some View {
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
            Button(L10n.string("Lock"), systemImage: "lock", action: lock)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help(L10n.string("Lock CopyTrading"))
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
                L10n.string(isShowingSettings ? model.settingsPage.title : model.selectedScreen.title),
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

    @ViewBuilder
    private var screenMenuItems: some View {
        ForEach(AppModel.ScreenSection.allCases) { section in
            if section != AppModel.ScreenSection.allCases.first {
                Divider()
            }
            ForEach(section.screens) { screen in
                Button(L10n.string(screen.title), systemImage: screen == model.selectedScreen ? "checkmark" : screen.symbol) {
                    model.selectedScreen = screen
                }
            }
        }
        Divider()
        ForEach(AppModel.sidebarFooterScreens) { screen in
            Button(L10n.string(screen.title), systemImage: screen == model.selectedScreen ? "checkmark" : screen.symbol) {
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

    private func liveRefresh() async {
        while !Task.isCancelled {
            await accountFeature.refresh(using: model.accountActions())
            await accountFeature.refreshHistories(using: model.accountActions())
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
        }
    }

    private func lock() {
        Task { await model.lockAccess() }
    }
}
