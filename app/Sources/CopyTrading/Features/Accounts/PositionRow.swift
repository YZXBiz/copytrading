import DesktopCore
import SwiftUI

/// One symbol the way a trader reads it: its name in the display face, shares, what they are worth,
/// a small ruler from average cost to today's price, and the gain or loss, from the broker's
/// valuation. When CopyTrading bought some, a chevron opens the lots that make them up and the line
/// under the symbol says how many posts they came from.
struct PositionRow: View {
    /// How far lots and the symbol column sit in from the chevron's edge.
    static let lotInset: CGFloat = 22
    /// The cost-to-price ruler's column, with room either side of the ruler.
    static let costColumnWidth: CGFloat = PositionCostMark.width + 36

    let position: AccountPositionView
    let isExpanded: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var posts: Int {
        Set(position.lots.map { $0.sourceID ?? $0.lotID }).count
    }

    var body: some View {
        if position.lots.isEmpty {
            // Shares held only outside CopyTrading have no lots to open; the row is plain.
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityIdentifier("accounts.position.\(position.symbol)")
        } else {
            Button(action: toggle) { content }
                .buttonStyle(QuietPressButtonStyle())
                .accessibilityLabel(accessibilityText)
                .accessibilityValue(L10n.string(isExpanded ? "Expanded" : "Collapsed"))
                .accessibilityHint(L10n.string("Shows the posts these shares came from"))
                .accessibilityIdentifier("accounts.position.\(position.symbol)")
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isExpanded)
                    .frame(width: Self.lotInset, alignment: .leading)
                    .opacity(position.lots.isEmpty ? 0 : 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.symbol)
                        .font(DesignTokens.cardTitle)
                        .foregroundStyle(Palette.ink)
                    if posts > 0 {
                        Text(L10n.string("from %@", Humanize.count(posts, "post")))
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            sharesCell
            moneyCell(position.marketValue)
            costCell
            gainCell
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    /// Average cost to today's price on the shared ruler, or a dash when the broker gave neither.
    private var costCell: some View {
        Group {
            if let cost = position.avgEntryPrice.flatMap({ Decimal(engine: $0) }),
                let price = position.currentPrice.flatMap({ Decimal(engine: $0) })
            {
                PositionCostMark(cost: cost, price: price)
            } else {
                Text(verbatim: "—").foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(width: Self.costColumnWidth)
    }

    private var owned: Decimal { Decimal(engine: position.ownedQty) ?? 0 }
    private var outside: Decimal { Decimal(engine: position.externalQty) ?? 0 }
    /// The broker's count, which the valuation is for; the ledger's when the broker was not read.
    private var shares: Decimal { position.brokerQty.flatMap { Decimal(engine: $0) } ?? owned + outside }

    /// Shares at the broker; a note says how many CopyTrading copied and how many are the owner's
    /// own, only when some are held outside it.
    @MainActor private var sharesCell: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(Self.quantity(shares))
                .font(DesignTokens.bodyText)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            // Only a mix needs saying; the limits strip already says what is held outside.
            if outside > 0, owned > 0 {
                Text(L10n.string("%@ copied · %@ outside", Self.shortQuantity(owned), Self.shortQuantity(outside)))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func moneyCell(_ value: String?) -> some View {
        Group {
            if let amount = value.flatMap({ Decimal(engine: $0) }) {
                MoneyText(value: amount, font: DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
            } else {
                Text(verbatim: "—").foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Gain or loss in dollars, coloured by direction, with the percent under it.
    @MainActor private var gainCell: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let gain = position.unrealizedPL.flatMap({ Decimal(engine: $0) }) {
                MoneyText(value: gain, style: .change, font: DesignTokens.bodyEmphasis)
                if let percent = position.unrealizedPLPercent.flatMap({ Decimal(engine: $0) }) {
                    Text(percent, format: .percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
                        .font(DesignTokens.caption)
                        .monospacedDigit()
                        .foregroundStyle(ChangeDirection(percent).color)
                }
            } else {
                Text(verbatim: "—").foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @MainActor private var accessibilityText: String {
        var parts = [L10n.string("%@, %@ shares", position.symbol, Self.quantity(shares))]
        if owned > 0 { parts.append(L10n.string("%@ copied", Self.quantity(owned))) }
        if posts > 0 { parts.append(L10n.string("from %@", Humanize.count(posts, "post"))) }
        if outside > 0 { parts.append(L10n.string("%@ held outside CopyTrading", Self.quantity(outside))) }
        if let price = position.currentPrice.flatMap({ Decimal(engine: $0) }) {
            parts.append(L10n.string("price %@", price.formatted(.currency(code: "USD"))))
        }
        if let gain = position.unrealizedPL.flatMap({ Decimal(engine: $0) }) {
            parts.append(ChangeDirection(gain).spoken(gain))
        }
        return Humanize.joined(parts)
    }

    /// Shares to at most four decimals: 2.8782, not 2.878194.
    static func quantity(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }

    /// Shares in a note, to at most two decimals: 12.72.
    static func shortQuantity(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Nothing copied, nothing outside, nothing at the broker: a symbol left over from an
    /// earlier position, with nothing to show.
    static func isEmpty(_ position: AccountPositionView) -> Bool {
        position.lots.isEmpty && (Decimal(engine: position.ownedQty) ?? 0) == 0
            && (Decimal(engine: position.externalQty) ?? 0) == 0
            && (position.brokerQty.flatMap { Decimal(engine: $0) } ?? 0) == 0
    }
}
