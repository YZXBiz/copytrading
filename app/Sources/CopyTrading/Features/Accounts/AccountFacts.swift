import DesktopCore
import SwiftUI

/// The account under its curve as one row across the full width: cash and buying power, then each
/// limit, every figure the same shape (a label over a number, a meter under a capped one) in equal
/// columns, and Edit Limits at the row's end. A narrow window folds it into two rows of three.
/// Nothing else on the page edits limits.
struct AccountFacts: View {
    let account: AccountOverview
    let policy: TradingAccountPolicy?
    let editLimits: () -> Void

    /// Room between columns, so a meter never runs into the next label.
    private static let gutter: CGFloat = 28

    /// Nil until the account's balance has been read, so an unread account never shows as empty.
    private var lossToday: Decimal? {
        guard let balance = account.balance else { return nil }
        guard let change = Decimal(engine: balance.dayChangeUSD), change < 0 else { return 0 }
        return -change
    }

    private var exposure: Decimal? {
        account.balance == nil ? nil : Decimal(engine: account.totalExposureUSD) ?? 0
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                row(cells, columns: cells.count)
                    .frame(minWidth: 820)
                editButton
                    .padding(.leading, 8)
            }
            VStack(alignment: .leading, spacing: 24) {
                row(Array(cells.prefix(3)), columns: 3)
                row(Array(cells.dropFirst(3)), columns: 3)
                editButton
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Equal columns, each figure's label on one line and its number on the next.
    private func row(_ cells: [AnyView], columns: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                cell
                    .padding(.trailing, Self.gutter)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(0..<max(0, columns - cells.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
    }

    private var cells: [AnyView] {
        var cells: [AnyView] = [
            AnyView(figure("Cash", Decimal(engine: account.balance?.cash), cents: true)),
            AnyView(figure("Buying power", Decimal(engine: account.balance?.buyingPower), cents: true)),
        ]
        if let policy {
            cells += [
                meter("Loss today", used: lossToday, cap: Decimal(engine: policy.dailyLossCapUSD), note: nil),
                meter("In stocks", used: exposure, cap: Decimal(engine: policy.maxTotalUSD), note: ExposureSplit.note(account)),
                AnyView(figure("Each order", Decimal(engine: policy.maxOrderUSD), suffix: L10n.string("at most"))),
                AnyView(figure("Each stock", Decimal(engine: policy.maxSymbolUSD), suffix: L10n.string("at most"))),
            ]
        }
        return cells
    }

    private var editButton: some View {
        Button(L10n.string("Edit Limits"), action: editLimits)
            .buttonStyle(QuietTextButtonStyle())
            .accessibilityIdentifier("account.editLimits")
            .fixedSize()
    }

    private func meter(_ title: String, used: Decimal?, cap: Decimal?, note: String?) -> AnyView {
        guard let cap else { return AnyView(figure(title, nil)) }
        return AnyView(LimitMeter(title: title, used: used, limit: cap, note: note))
    }

    /// A label over a number, with an optional quiet word after it: "$500 at most".
    private func figure(_ title: String, _ amount: Decimal?, cents: Bool = false, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(L10n.string(title))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let amount {
                    MoneyText(
                        value: amount, font: DesignTokens.statValue,
                        fractionDigits: cents ? nil : 0
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
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
