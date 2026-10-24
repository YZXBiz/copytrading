import DesktopCore
import SwiftUI

/// The account's rules: every limit in one bordered group under a "Limits" title, with Edit Limits
/// beside it. Each is a label and an amount; today's loss and what is invested add their cap and a
/// meter, which shows the room left without saying it. In the side rail the four stack as a list.
/// Nothing else on the page edits limits.
struct AccountFacts: View {
    let account: AccountOverview
    let policy: TradingAccountPolicy?
    /// The limits sit in the narrow side rail, one under another.
    let isCompact: Bool
    let editLimits: () -> Void

    private struct Cell {
        let title: String
        let amount: Decimal?
        /// "of $250" after a used amount.
        let suffix: String
        /// How full the meter is, for a limit that fills up.
        let fraction: Double?
        /// Only what the amount can't say: how much of it the owner holds outside CopyTrading.
        let footnote: String?
    }

    /// Nil until the account's balance has been read, so an unread account never shows as empty.
    private var lossToday: Decimal? {
        guard let balance = account.balance else { return nil }
        guard let change = Decimal(engine: balance.dayChangeUSD), change < 0 else { return 0 }
        return -change
    }

    var body: some View {
        if let policy {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(L10n.string("Limits"))
                        .font(DesignTokens.bodyEmphasis.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Button(L10n.string("Edit Limits"), action: editLimits)
                        .buttonStyle(QuietTextButtonStyle())
                        .accessibilityIdentifier("account.editLimits")
                }
                group(cells(policy))
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func group(_ cells: [Cell]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        Group {
            if isCompact {
                VStack(spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                        if index > 0 { Divider().overlay(Palette.hairline) }
                        listRow(cell)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                        if index > 0 { Divider().overlay(Palette.hairline) }
                        column(cell)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 1) }
    }

    private func cells(_ policy: TradingAccountPolicy) -> [Cell] {
        let exposure = account.balance == nil ? nil : Decimal(engine: account.totalExposureUSD) ?? 0
        let money = Decimal.FormatStyle.Currency(code: "USD").precision(.fractionLength(0))
        func filling(_ title: String, used: Decimal?, cap: Decimal?, note: String?) -> Cell {
            guard let cap else { return Cell(title: title, amount: nil, suffix: "", fraction: nil, footnote: nil) }
            return Cell(
                title: title, amount: used, suffix: L10n.string("of %@", cap.formatted(money)),
                fraction: used.map { cap > 0 ? min(1, max(0, ($0 / cap).doubleValue)) : 0 } ?? 0,
                footnote: note)
        }
        return [
            filling("Loss today", used: lossToday, cap: Decimal(engine: policy.dailyLossCapUSD), note: nil),
            filling(
                "Invested", used: exposure, cap: Decimal(engine: policy.maxTotalUSD), note: ExposureSplit.note(account)),
            Cell(title: "Each order", amount: Decimal(engine: policy.maxOrderUSD), suffix: "", fraction: nil, footnote: nil),
            Cell(title: "Each symbol", amount: Decimal(engine: policy.maxSymbolUSD), suffix: "", fraction: nil, footnote: nil),
        ]
    }

    /// A column of the four-across row: label, amount, then the meter (or its room).
    private func column(_ cell: Cell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(cell.title))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
            amount(cell)
            meter(cell.fraction)
                .opacity(cell.fraction == nil ? 0 : 1)
            footnote(cell)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A row of the rail's list: label and amount on one line, the meter, then the footnote.
    private func listRow(_ cell: Cell) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string(cell.title))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                Spacer(minLength: 8)
                amount(cell)
            }
            if let fraction = cell.fraction {
                meter(fraction).padding(.top, 2)
            }
            footnote(cell)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func amount(_ cell: Cell) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let value = cell.amount {
                MoneyText(value: value, font: DesignTokens.bodyEmphasis.weight(.semibold), fractionDigits: 0)
                    .foregroundStyle(Palette.ink)
                if !cell.suffix.isEmpty {
                    Text(cell.suffix)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            } else {
                // Not read yet: a dash, never a $0 that reads as an empty account.
                Text(verbatim: "—")
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .monospacedDigit()
    }

    @ViewBuilder
    private func footnote(_ cell: Cell) -> some View {
        if let footnote = cell.footnote {
            Text(footnote)
                .font(DesignTokens.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
        }
    }

    /// Sky while there is room, butter once it is close enough to look at, blush at the cap.
    private func meter(_ fraction: Double?) -> some View {
        let fraction = fraction ?? 0
        let tint = fraction >= 1 ? Palette.blush : fraction >= 0.8 ? Palette.butter : Palette.sky
        return Capsule()
            .fill(Palette.hairline)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(tint).frame(width: max(fraction > 0 ? 4 : 0, proxy.size.width * fraction))
                }
            }
            .accessibilityHidden(true)
    }
}
