import DesktopCore
import SwiftUI

/// One block of shares under its position, as one clean line: whose post bought it and when, what
/// the post said, then "0.885 shares · bought $110.75 · now $110.75"; the lot's own gain on the right,
/// a quiet "Open post ↗" back to the post, and a black Sell pill.
struct PositionLotRow: View {
    let lot: AccountLotView
    let guruName: String?
    /// Today's price of the symbol, from the position's valuation.
    let currentPrice: Decimal?
    /// The post in loaded Activity, when it is there to open.
    let post: SourceActivity?
    let openPost: (SourceActivity) -> Void
    let sell: () -> Void
    @State private var hoversOpen = false

    @MainActor private var who: String {
        guard lot.sourceID != nil else { return L10n.string("Earlier buy") }
        return guruName ?? L10n.string("A post")
    }

    private var remaining: Decimal { Decimal(engine: lot.remainingQty) ?? 0 }
    private var bought: Decimal? { Decimal(engine: lot.averagePrice) }

    /// "12 shares", or "5 of 12 shares" once some of the lot is sold, for VoiceOver.
    @MainActor private var shares: String {
        let original = Decimal(engine: lot.originalQty) ?? remaining
        guard original != remaining else { return Humanize.shares(remaining) }
        return Humanize.shares(remaining, of: original)
    }

    /// "0.885 shares · bought $110.75 · now $110.75"; a partly sold lot says "0.5 of 2 shares".
    @MainActor private var numbers: String {
        let original = Decimal(engine: lot.originalQty) ?? remaining
        var parts = [
            original == remaining
                ? Humanize.shares(remaining)
                : Humanize.shares(remaining, of: original)
        ]
        if let bought { parts.append(L10n.string("bought %@", bought.formatted(.currency(code: "USD")))) }
        if let currentPrice { parts.append(L10n.string("now %@", currentPrice.formatted(.currency(code: "USD")))) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    GuruMonogram(name: who, size: 20)
                    Text(who)
                        .font(DesignTokens.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                    Text(Humanize.postTime(lot.postedAt ?? lot.boughtAt))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                }
                if let excerpt = lot.excerpt {
                    Text("“\(excerpt)”")
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                } else if lot.sourceID == nil {
                    Text(L10n.string("The buy that opened these shares is no longer on record."))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(numbers)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            gain
            openButton
            Button(L10n.string("Sell"), action: sell)
                .buttonStyle(PageButtonStyle(isProminent: true, horizontalPadding: 18))
                .accessibilityLabel(L10n.string("Sell %@ from %@", shares, who))
                .accessibilityIdentifier("accounts.lot.sell.\(lot.lotID)")
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
    }

    /// The lot's gain or loss, with the percent from what it cost to today's price under it.
    @ViewBuilder
    private var gain: some View {
        if let gain = lot.unrealizedPL.flatMap({ Decimal(engine: $0) }) {
            VStack(alignment: .trailing, spacing: 1) {
                MoneyText(value: gain, style: .change, font: DesignTokens.bodyEmphasis)
                if let bought, bought != 0, let currentPrice {
                    let percent = (currentPrice - bought) / bought
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
