import DesktopCore
import SwiftUI

/// The account's rules under its curve: every limit in one place under a "Limits" title, with Edit
/// Limits beside it: today's loss and what is in stocks, each against its cap with a meter, and the
/// most an order and a stock may take. Each figure has the same shape, a label over a number, so the
/// row reads straight across. Cash and buying power sit with the balance above. Nothing else on the
/// page edits limits.
struct AccountFacts: View {
    let account: AccountOverview
    let policy: TradingAccountPolicy?
    let editLimits: () -> Void

    private static let column: CGFloat = 176

    /// Nil until the account's balance has been read, so an unread account never shows as empty.
    private var lossToday: Decimal? {
        guard let balance = account.balance else { return nil }
        guard let change = Decimal(engine: balance.dayChangeUSD), change < 0 else { return 0 }
        return -change
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            if let policy {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(L10n.string("Limits"))
                            .font(DesignTokens.cardTitle)
                            .tracking(DesignTokens.listHeadingTracking)
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Button(L10n.string("Edit Limits"), action: editLimits)
                            .buttonStyle(QuietTextButtonStyle())
                            .accessibilityIdentifier("account.editLimits")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 0) { limits(policy) }
                        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 22) {
                            let cells = limitCells(policy)
                            GridRow {
                                cells.0; cells.1
                            }
                            GridRow {
                                cells.2; cells.3
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func limits(_ policy: TradingAccountPolicy) -> some View {
        let cells = limitCells(policy)
        cells.0
        cells.1
        cells.2
        cells.3
    }

    private func limitCells(_ policy: TradingAccountPolicy) -> (AnyView, AnyView, AnyView, AnyView) {
        let exposure = account.balance == nil ? nil : Decimal(engine: account.totalExposureUSD) ?? 0
        return (
            meter("Loss today", used: lossToday, cap: Decimal(engine: policy.dailyLossCapUSD), note: nil),
            meter("In stocks", used: exposure, cap: Decimal(engine: policy.maxTotalUSD), note: ExposureSplit.note(account)),
            AnyView(figure("Each order", Decimal(engine: policy.maxOrderUSD), suffix: L10n.string("at most"))),
            AnyView(figure("Each stock", Decimal(engine: policy.maxSymbolUSD), suffix: L10n.string("at most")))
        )
    }

    private func meter(_ title: String, used: Decimal?, cap: Decimal?, note: String?) -> AnyView {
        guard let cap else { return AnyView(figure(title, nil)) }
        return AnyView(
            LimitMeter(title: title, used: used, limit: cap, note: note)
                .frame(width: Self.column - 32, alignment: .leading)
                .frame(width: Self.column, alignment: .leading))
    }

    /// A label over a number, with an optional quiet word after it: "$500 at most".
    private func figure(_ title: String, _ amount: Decimal?, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(L10n.string(title))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let amount {
                    MoneyText(
                        value: amount, font: DesignTokens.statValue,
                        fractionDigits: 0
                    )
                    .foregroundStyle(Palette.ink)
                    if let suffix {
                        Text(suffix)
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                } else {
                    // Not read yet: a dash, never a $0 that reads as an empty account.
                    Text("—")
                        .font(DesignTokens.statValue)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
        }
        .frame(width: Self.column, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
