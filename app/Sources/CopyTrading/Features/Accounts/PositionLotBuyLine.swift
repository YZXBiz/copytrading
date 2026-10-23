import DesktopCore
import SwiftUI

/// One buy in a lot, as one clean line: whose post bought it and when, what the post said, then
/// "0.885 shares bought at $110.75   now $111.35"; the buy's own gain on the right, and a quiet
/// "Open post ↗" back to the post.
struct PositionLotBuyLine: View {
    let buy: AccountLotBuyView
    /// The stock, or the coin's pair, the buy bought.
    let symbol: String
    let who: String
    /// Today's price of the symbol, from the position's valuation.
    let currentPrice: Decimal?
    /// The post in loaded Activity, when it is there to open.
    let post: SourceActivity?
    let openPost: (SourceActivity) -> Void
    @State private var hoversOpen = false

    private var remaining: Decimal { Decimal(engine: buy.remainingQty) ?? 0 }
    private var price: Decimal? { buy.price.flatMap { Decimal(engine: $0) } }

    /// "0.885 shares bought at $110.75", or "0.5 of 2 shares bought at $40" once some are sold.
    /// Shares show to three decimals, as a broker statement does, never with an "≈"; a coin shows
    /// to the billionth with its code, "0.001231481 BTC bought at $81,000.00".
    @MainActor private var holding: String {
        let bought = Decimal(engine: buy.boughtQty) ?? remaining
        let shares: String
        if Humanize.isCoin(symbol) {
            shares =
                bought == remaining
                ? Humanize.shares(remaining, of: symbol) : Humanize.shares(remaining, of: bought, symbol: symbol)
        } else {
            let count = Self.count(remaining)
            shares =
                bought == remaining
                ? L10n.string(remaining == 1 ? "%@ share" : "%@ shares", count)
                : L10n.string(bought == 1 ? "%@ of %@ share" : "%@ of %@ shares", count, Self.count(bought))
        }
        guard let price else { return shares }
        return L10n.string("%@ bought at %@", shares, price.formatted(.currency(code: "USD")))
    }

    private static func count(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    GuruMonogram(name: who, size: 20)
                    Text(who)
                        .font(DesignTokens.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                    Text(Humanize.postTime(buy.postedAt ?? buy.boughtAt))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                }
                if let excerpt = buy.excerpt {
                    Text("“\(excerpt)”")
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                } else if buy.sourceID == nil {
                    Text(L10n.string("The buy that opened these shares is no longer on record."))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(holding)
                        .foregroundStyle(Palette.tertiaryInk)
                    if let currentPrice {
                        Text(L10n.string("now %@", currentPrice.formatted(.currency(code: "USD"))))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .font(DesignTokens.caption)
                .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            gain
            openButton
        }
        .accessibilityElement(children: .contain)
    }

    /// The buy's gain or loss, with the percent from what it cost to today's price under it.
    @ViewBuilder
    private var gain: some View {
        if let gain = buy.unrealizedPL.flatMap({ Decimal(engine: $0) }) {
            VStack(alignment: .trailing, spacing: 1) {
                MoneyText(value: gain, style: .change, font: DesignTokens.bodyEmphasis)
                if let price, price != 0, let currentPrice {
                    let percent = (currentPrice - price) / price
                    Text(percent, format: .percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
                        .font(DesignTokens.caption)
                        .monospacedDigit()
                        .foregroundStyle(ChangeDirection(percent).color)
                }
            }
            .fixedSize()
        }
    }

    /// Back to the post in Activity: quiet words with a ↗, marked in butter under the pointer.
    private var openButton: some View {
        Button {
            if let post { openPost(post) }
        } label: {
            HStack(spacing: 3) {
                Text(L10n.string("Open post"))
                    .markerHighlight(hoversOpen && post != nil)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .fontWeight(.medium)
            }
            .font(DesignTokens.caption.weight(.medium))
            .foregroundStyle(Palette.secondaryInk)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .disabled(post == nil)
        .onHover { hoversOpen = $0 }
        .help(L10n.string(post == nil ? "This post is older than what Activity has loaded" : "Open the post in Activity"))
        .fixedSize()
    }
}
