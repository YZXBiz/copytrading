import DesktopCore
import SwiftUI
import TipKit

/// With two or more accounts, while copying runs: how many it copies into, and Stop All. Starting
/// and stopping one account is that account's own button, so with one account the toolbar shows
/// nothing and never repeats it.
struct CopyingControl: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    @Environment(\.tipGeneration) private var tipGeneration

    private var accountCount: Int { model.savedTradingConfiguration?.accounts.count ?? 0 }

    private var copyingCount: Int {
        accountFeature.accounts.filter { AccountCopyState($0).isCopying }.count
    }

    var body: some View {
        if model.isCopyingRunning, accountCount > 1 {
            HStack(spacing: 10) {
                Text(L10n.string("Copying into %lld of %lld", Int64(copyingCount), Int64(accountCount)))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
                Button(L10n.string("Stop All"), systemImage: "stop.fill", action: stop)
                    .labelStyle(.titleAndIcon)
                    .disabled(model.isTradingCommandPending || model.tradingStatus?.state == .pausing)
                    .help(L10n.string("Stop reading new posts and placing orders for every account."))
                    // On macOS the arrow edge is the side the tip opens on: below, inside the window.
                    .popoverTip(PauseCopyingTip(generation: tipGeneration), arrowEdge: .bottom)
                    .accessibilityIdentifier("toolbar.copying")
            }
            .task { await PauseCopyingTip.copyingStarted.donate() }
        }
    }

    private func stop() {
        Task { await model.pauseTrading() }
    }
}
