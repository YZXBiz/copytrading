import DesktopCore
import SwiftUI
import TipKit

/// The master switch: start or pause copying every account, one click from any screen.
struct CopyingControl: View {
    @Bindable var model: AppModel
    @State private var confirmLiveStart = false
    @Environment(\.tipGeneration) private var tipGeneration

    private var state: TradingRunState? { model.tradingStatus?.state }

    private var isActive: Bool {
        state == .running || state == .degraded || state == .starting
    }

    private var canCommand: Bool {
        model.savedTradingConfiguration != nil && model.tradingStatus != nil
            && !model.isTradingCommandPending && state != .pausing
    }

    var body: some View {
        Group {
            if isActive {
                Button(L10n.string("Pause Copying"), systemImage: "pause.fill", action: pause)
                    .help(L10n.string("Stop reading new posts and placing orders for every account."))
                    .popoverTip(PauseCopyingTip(generation: tipGeneration), arrowEdge: .top)
            } else {
                Button(L10n.string("Start Copying"), systemImage: "play.fill", action: requestStart)
                    .help(
                        model.savedTradingConfiguration == nil
                            ? L10n.string("Finish Getting Started before copying.")
                            : L10n.string("Read new posts and copy them into your accounts.")
                    )
            }
        }
        .labelStyle(.titleAndIcon)
        .disabled(!canCommand)
        .task(id: isActive) {
            if isActive { await PauseCopyingTip.copyingStarted.donate() }
        }
        .accessibilityIdentifier("toolbar.copying")
        .confirmationDialog(
            L10n.string("Start copying into live accounts?"),
            isPresented: $confirmLiveStart,
            titleVisibility: .visible
        ) {
            Button(L10n.string("Start Live Copying"), role: .destructive, action: start)
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("Live accounts can place real orders. Every connection is checked again before copying starts."))
        }
    }

    private func requestStart() {
        if model.hasLiveAccounts {
            confirmLiveStart = true
        } else {
            start()
        }
    }

    private func start() {
        Task { await model.startTrading() }
    }

    private func pause() {
        Task { await model.pauseTrading() }
    }
}
