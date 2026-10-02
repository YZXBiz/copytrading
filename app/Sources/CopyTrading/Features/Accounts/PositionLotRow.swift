import DesktopCore
import SwiftUI

/// One block of shares under its position: whose post bought it, when, what it said, how many
/// shares are left of it and at what price, a way back to the post, and Sell.
struct PositionLotRow: View {
    let lot: AccountLotView
    let guruName: String?
    /// The post in loaded Activity, when it is there to open.
    let post: SourceActivity?
    let openPost: (SourceActivity) -> Void
    let sell: () -> Void

    @MainActor private var who: String {
        guard lot.sourceID != nil else { return L10n.string("Earlier buy") }
        return guruName ?? L10n.string("A post")
    }

    /// "12 shares", or "5 of 12 shares" once some of the lot is sold.
    @MainActor private var shares: String {
        let remaining = Decimal(engine: lot.remainingQty) ?? 0
        let original = Decimal(engine: lot.originalQty) ?? remaining
        guard original != remaining else {
            return L10n.string("%@ %@", remaining.formatted(), L10n.string(remaining == 1 ? "share" : "shares"))
        }
        return L10n.string("%@ of %@ shares", remaining.formatted(), original.formatted())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GuruMonogram(name: who, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(who)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.ink)
                    Text(Humanize.timestamp(lot.postedAt ?? lot.boughtAt))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                if let excerpt = lot.excerpt {
                    Text("“\(excerpt)”")
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                } else if lot.sourceID == nil {
                    Text(L10n.string("The buy that opened these shares is no longer on record."))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(shares)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                if let price = Decimal(engine: lot.averagePrice) {
                    HStack(spacing: 4) {
                        Text(L10n.string("bought at"))
                        MoneyText(value: price, font: DesignTokens.caption)
                    }
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                }
            }
            Button(L10n.string("Open Post"), systemImage: "arrow.up.forward.square") {
                if let post { openPost(post) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.tertiaryInk)
            .disabled(post == nil)
            .help(L10n.string(post == nil ? "This post is older than what Activity has loaded" : "Open the post in Activity"))
            Button(L10n.string("Sell…"), action: sell)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel(L10n.string("Sell %@ from %@", shares, who))
                .accessibilityIdentifier("accounts.lot.sell.\(lot.lotID)")
        }
        .font(DesignTokens.bodyText)
        .padding(.vertical, 9)
        .accessibilityElement(children: .contain)
    }
}
