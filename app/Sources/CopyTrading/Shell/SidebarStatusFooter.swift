import SwiftUI

/// Always-visible answer to "is it copying?" regardless of the selected screen.
struct SidebarStatusFooter: View {
    let model: AppModel

    @MainActor private var summary: (text: String, tone: StatusTone) {
        if model.runtimeState == .stopped || model.runtimeState == .failed {
            return (L10n.string("Engine stopped"), StatusTone(model.runtimeState))
        }
        guard model.savedTradingConfiguration != nil else { return (L10n.string("Not set up yet"), .inactive) }
        return CopyingSummary.of(model.tradingStatus)
    }

    @MainActor private var helpText: String {
        let count = model.tradingStatus?.activeAccounts ?? 0
        return model.tradingStatus?.state == .running
            ? L10n.string("Copying new posts into %@", Humanize.count(count, "account"))
            : summary.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 14) {
                ForEach(AppModel.sidebarFooterScreens) { screen in
                    Button {
                        model.selectedScreen = screen
                    } label: {
                        Image(systemName: screen.symbol)
                            .symbolVariant(model.selectedScreen == screen ? .fill : .none)
                            .foregroundStyle(model.selectedScreen == screen ? Palette.accent : .secondary)
                    }
                    .help(screen == .settings ? L10n.string("Settings (⌘,)") : L10n.string(screen.title))
                    .accessibilityLabel(L10n.string(screen.title))
                    .accessibilityIdentifier("navigation.\(screen.rawValue)")
                }
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    Circle()
                        .fill(summary.tone.color)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(summary.text)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(helpText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.string("Status: %@", summary.text))
            }
            .buttonStyle(.borderless)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}
