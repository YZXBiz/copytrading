import SwiftUI

/// The card under the Settings sidebar's icon: whether this copy of CopyTrading is copying, and
/// into what, on the app's chart paper.
struct SettingsSummaryCard: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var state: (text: String, tone: StatusTone) {
        if model.runtimeState == .stopped || model.runtimeState == .failed {
            return (L10n.string("Engine stopped"), StatusTone(model.runtimeState))
        }
        guard model.savedTradingConfiguration != nil else { return (L10n.string("Not set up yet"), .inactive) }
        return CopyingSummary.of(model.tradingStatus)
    }

    private var summary: String {
        guard let configuration = model.savedTradingConfiguration else {
            return L10n.string("Getting Started takes about ten minutes. Everything stays on this Mac.")
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
