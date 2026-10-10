import AppKit
import DesktopCore
import SwiftUI

/// The menu bar panel: today's money, the latest call, and the copying switch, one glance away.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel

    private var state: TradingRunState? { model.tradingStatus?.state }
    private var isEngineStopped: Bool { model.runtimeState == .stopped || model.runtimeState == .failed }
    private var isCopying: Bool { model.isCopying }

    private var balances: [AccountBalance] {
        accountFeature.accounts.filter(\.activeConfiguration).compactMap(\.balance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)
            if model.isTradingUnlocked {
                hero
                MenuBarSparkline(accounts: accountFeature.accounts, histories: accountFeature.histories)
                    .padding(.top, 10)
                latestCall
                    .padding(.top, 14)
            } else {
                Label(L10n.string("Locked. Open CopyTrading to unlock."), systemImage: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let message = model.runtimeStopMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.top, 10)
            }
            let waiting = model.agentProposals.filter { $0.state == .pending }.count
            if waiting > 0 {
                Label(L10n.string("%@ waiting for approval", Humanize.count(waiting, "agent request")), systemImage: "hand.raised.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                    .padding(.top, 10)
            }
            Divider()
                .padding(.vertical, 10)
            actions
        }
        .padding(14)
        .frame(width: 320)
        .tint(Palette.ink)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.page)
                .frame(width: 24, height: 24)
                .background(Palette.ink, in: .rect(cornerRadius: 6))
                .accessibilityHidden(true)
            Text(L10n.string("CopyTrading"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(statusTone.color)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Today's change as the one big number, with the balance and post count underneath.
    private var hero: some View {
        let change = balances.compactMap { Decimal(engine: $0.dayChangeUSD) }.reduce(0, +)
        let equity = balances.compactMap { Decimal(engine: $0.equity) }.reduce(0, +)
        let posts = accountFeature.activity.filter(\.isToday).count
        return VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string("Today"))
                .font(.system(size: 12))
                .foregroundStyle(Palette.tertiaryInk)
            if balances.isEmpty {
                Text("—")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            } else {
                MoneyText(value: change, style: .change, font: .system(size: 26, weight: .semibold))
            }
            Text(
                balances.isEmpty
                    ? L10n.string("%@ today", Humanize.count(posts, "post"))
                    : L10n.string("Balance %@ · %@ today", equity.formatted(.currency(code: "USD")), Humanize.count(posts, "post"))
            )
            .font(.system(size: 12))
            .foregroundStyle(Palette.tertiaryInk)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var latestCall: some View {
        if let item = accountFeature.activity.first {
            let guru = GuruDirectory(model.savedTradingConfiguration).name(for: item.guruID)
            HStack(alignment: .center, spacing: 10) {
                GuruMonogram(name: guru ?? "?", size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.headline)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let date = item.sourceDate {
                        Text(
                            L10n.string(
                                "Latest call · %@",
                                date.formatted(
                                    .relative(presentation: .named)
                                        .locale(AppLanguagePreference.shared.language.locale)
                                )
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiaryInk)
                    }
                }
                Spacer(minLength: 4)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Open CopyTrading", symbol: "macwindow", action: openMainWindow)
            if model.savedTradingConfiguration != nil, model.tradingStatus != nil, model.isTradingUnlocked {
                if isCopying {
                    MenuRow(title: "Pause Copying", symbol: "pause", action: pause)
                        .disabled(model.isTradingCommandPending)
                } else if !model.hasLiveAccounts {
                    MenuRow(title: "Start Copying", symbol: "play", action: start)
                        .disabled(model.isTradingCommandPending)
                }
            }
            if isEngineStopped {
                MenuRow(title: "Start Engine", symbol: "power", action: model.requestStart)
            } else {
                MenuRow(title: "Settings…", symbol: "gearshape", shortcut: "⌘,", action: openSettings)
            }
            MenuRow(title: "Quit CopyTrading", symbol: "power", shortcut: "⌘Q", action: quit)
                .keyboardShortcut("q")
        }
    }

    @MainActor private var statusText: String {
        if isEngineStopped { return L10n.string("Engine stopped") }
        guard model.savedTradingConfiguration != nil else { return L10n.string("Not set up") }
        switch state {
        case .running: return L10n.string("Copying")
        case .degraded: return L10n.string("Needs attention")
        case .starting: return L10n.string("Starting")
        case .pausing: return L10n.string("Pausing")
        case .failed: return L10n.string("Stopped")
        case .paused, nil: return L10n.string("Paused")
        }
    }

    private var statusTone: StatusTone {
        isEngineStopped ? StatusTone(model.runtimeState) : StatusTone(state)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate()
    }

    private func openSettings() {
        model.selectedScreen = .settings
        openMainWindow()
    }

    private func start() { Task { await model.startTrading() } }
    private func pause() { Task { await model.pauseTrading() } }
    private func quit() { NSApplication.shared.terminate(nil) }
}
