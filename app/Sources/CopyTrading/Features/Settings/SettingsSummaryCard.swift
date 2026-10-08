import SwiftUI

/// The card under the Settings sidebar's icon: whether this copy of CopyTrading is copying, and
/// into what, on the app's chart paper.
struct SettingsSummaryCard: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

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
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(state.text)
                    .font(.system(.body, weight: .semibold).scaled(by: 14.0 / 13))
                    .foregroundStyle(Palette.ink)
            }
            Text(summary)
                .font(.body)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ChartPaperBackdrop(focus: UnitPoint(x: 0.6, y: 1), gridSpacing: 16)
        }
        .overlay(alignment: .bottom) {
            RisingLineFlourish(lineWidth: 2)
                .frame(height: 22)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    contrast == .increased ? Palette.secondaryInk : .white.opacity(colorScheme == .dark ? 0.08 : 0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }
}
