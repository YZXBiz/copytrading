import SwiftUI

/// The lines under the Settings sidebar's name: whether this copy of CopyTrading is copying, and
/// into what. Plain words with a hairline under them, no card.
struct SettingsSummaryCard: View {
    let model: AppModel

    private var engineStopped: Bool { model.runtimeState == .stopped || model.runtimeState == .failed }

    /// Before a first start the card is about the setup; afterwards, about copying. A stopped
    /// engine is said once, in the place it matters.
    private var state: (text: String, tone: StatusTone) {
        guard model.savedTradingConfiguration != nil else {
            return (L10n.string(model.setupProgress.completed == 0 ? "Not set up yet" : "Setting up"), .inactive)
        }
        if engineStopped { return (L10n.string("Engine stopped"), StatusTone(model.runtimeState)) }
        return CopyingSummary.of(model.tradingStatus)
    }

    private var summary: String {
        guard let configuration = model.savedTradingConfiguration else {
            let progress = model.setupProgress
            var lines: [String] = []
            if progress.completed == 0 {
                lines.append(L10n.string("Getting Started takes about ten minutes. Everything stays on this Mac."))
            } else {
                lines.append(L10n.string("%lld of %lld steps done", Int64(progress.completed), Int64(progress.total)))
                if let next = progress.next { lines.append(L10n.string("Next: %@.", L10n.string(next.title))) }
            }
            if engineStopped { lines.append(L10n.string("The engine is stopped; start it in Settings, Engine.")) }
            return lines.joined(separator: "\n")
        }
        let gurus = Humanize.count(GuruDirectory(configuration).gurus.count, "guru")
        let accounts = Humanize.count(configuration.accounts.count, "account")
        return L10n.string("Copies %@ into %@. Your keys stay in this Mac's Keychain.", gurus, accounts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.tone.color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(state.text)
                    .font(DesignTokens.sidebarTitle)
                    .foregroundStyle(Palette.ink)
            }
            Text(summary)
                .font(DesignTokens.sidebarDetail)
                .foregroundStyle(Palette.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)

        .accessibilityElement(children: .combine)
    }
}
