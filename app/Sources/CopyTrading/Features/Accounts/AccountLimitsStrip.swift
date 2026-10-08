import DesktopCore
import SwiftUI

/// The account's limits in one outlined strip: how much of today's loss and of its stock budget
/// is used, the per-order and per-stock caps, and a way to change them.
struct AccountLimitsStrip: View {
    let account: AccountOverview
    let policy: TradingAccountPolicy
    /// Beside a detail pane, the per-stock cap gives way.
    var isCompact = false
    let editLimits: () -> Void

    private var lossToday: Decimal {
        guard let change = Decimal(engine: account.balance?.dayChangeUSD), change < 0 else { return 0 }
        return -change
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) { items }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 24) { meters }
                HStack(spacing: 24) { caps }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Palette.hairline)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Limits"))
    }

    @ViewBuilder
    private var items: some View {
        meters
        Hairline(vertical: true).frame(height: 28)
        caps
    }

    @ViewBuilder
    private var meters: some View {
        if let dailyCap = Decimal(engine: policy.dailyLossCapUSD) {
            LimitMeter(title: "Loss today", used: lossToday, limit: dailyCap)
                .frame(minWidth: 160, maxWidth: 220)
        }
        if let totalCap = Decimal(engine: policy.maxTotalUSD) {
            LimitMeter(
                title: "In stocks", used: Decimal(engine: account.totalExposureUSD) ?? 0, limit: totalCap,
                note: ExposureSplit.note(account)
            )
            .frame(minWidth: 160, maxWidth: 220)
        }
    }

    @ViewBuilder
    private var caps: some View {
        cap("Per order", policy.maxOrderUSD)
        if !isCompact {
            cap("Per stock", policy.maxSymbolUSD)
        }
        Spacer(minLength: 8)
        Button(L10n.string("Edit Limits"), action: editLimits)
            .buttonStyle(PageButtonStyle())
            .accessibilityIdentifier("account.editLimits")
    }

    private func cap(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string(title))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
            Text(Decimal(engine: value)?.formatted(.currency(code: "USD").precision(.fractionLength(0))) ?? value)
                .font(DesignTokens.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
