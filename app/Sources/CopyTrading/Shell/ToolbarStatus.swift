import DesktopCore
import SwiftUI

/// How fresh the numbers are, as plain text; pressing it reads everything again.
struct ToolbarStatus: View {
    let model: AppModel
    let accountFeature: AccountFeatureModel

    private var isCopying: Bool {
        model.tradingStatus?.state == .running || model.tradingStatus?.state == .degraded
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: refresh) {
                // Before setup there is nothing to be fresh about.
                ViewThatFits(in: .horizontal) {
                    freshness(compact: false)
                    freshness(compact: true)
                }
            }
            .buttonStyle(.plain)
            .help(L10n.string("Read accounts and activity again"))
            .accessibilityIdentifier("toolbar.refresh")
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 6)
    }

    private func freshness(compact: Bool) -> some View {
        FreshnessLabel(
            updatedAt: model.savedTradingConfiguration == nil ? nil : accountFeature.lastUpdatedAt,
            isCopying: isCopying, compact: compact
        )
    }

    private func refresh() {
        Task {
            await accountFeature.refresh(using: model.accountActions())
            await accountFeature.refreshHistories(using: model.accountActions())
        }
    }
}
