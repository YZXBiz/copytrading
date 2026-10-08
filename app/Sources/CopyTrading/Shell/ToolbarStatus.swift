import DesktopCore
import SwiftUI

/// How fresh the numbers are, as plain text; pressing it reads everything again.
struct ToolbarStatus: View {
    let model: AppModel
    let accountFeature: AccountFeatureModel

    private var isCopying: Bool { model.isCopying }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: refresh) {
                // Before setup there is nothing to be fresh about.
                HStack(spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        freshness(compact: false)
                        freshness(compact: true)
                    }
                    if model.savedTradingConfiguration != nil {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .background(Palette.group.opacity(0.6), in: .capsule)
            .help(L10n.string("Refresh now"))
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
