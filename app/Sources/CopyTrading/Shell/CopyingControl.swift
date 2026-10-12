import DesktopCore
import SwiftUI
import TipKit

/// While copying runs: how many accounts it copies into, and one Stop that stops it everywhere.
/// Starting is each account's own Start Copying, on its page, so the toolbar never repeats it.
struct CopyingControl: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    @Environment(\.tipGeneration) private var tipGeneration

    private var accountCount: Int { model.savedTradingConfiguration?.accounts.count ?? 0 }

    private var copyingCount: Int {
        accountFeature.accounts.filter { AccountCopyState($0).isCopying }.count
    }

    var body: some View {
        if model.isCopyingRunning {
            HStack(spacing: 10) {
                if accountCount > 1 {
                    Text(L10n.string("Copying into %lld of %lld", Int64(copyingCount), Int64(accountCount)))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                }
                Button(
                    L10n.string(accountCount > 1 ? "Stop All" : "Stop Copying"), systemImage: "stop.fill", action: stop
                )
                .labelStyle(.titleAndIcon)
                .disabled(model.isTradingCommandPending || model.tradingStatus?.state == .pausing)
                .help(L10n.string("Stop reading new posts and placing orders for every account."))
                .popoverTip(PauseCopyingTip(generation: tipGeneration), arrowEdge: .top)
                .accessibilityIdentifier("toolbar.copying")
            }
            .task { await PauseCopyingTip.copyingStarted.donate() }
        }
    }

    private func stop() {
        Task { await model.pauseTrading() }
    }
}
