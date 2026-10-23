import DesktopCore
import SwiftUI

/// One block of shares under its position: every buy of the stock from one guru (ADR-0010), each
/// as its own line with its post, price, and gain, and one black Sell pill for the whole lot.
struct PositionLotRow: View {
    let lot: AccountLotView
    /// The stock, or the coin's pair, the lot holds.
    let symbol: String
    let guruName: String?
    /// Today's price of the symbol, from the position's valuation.
    let currentPrice: Decimal?
    /// A buy's post in loaded Activity, when it is there to open.
    let post: (AccountLotBuyView) -> SourceActivity?
    let openPost: (SourceActivity) -> Void
    let sell: () -> Void

    @MainActor private var who: String {
        guard lot.sourceID != nil else { return L10n.string("Earlier buy") }
        return guruName ?? L10n.string("A post")
    }

    private var remaining: Decimal { Decimal(engine: lot.remainingQty) ?? 0 }

    /// "12 shares", or "5 of 12 shares" once some of the lot is sold, for VoiceOver.
    @MainActor private var shares: String {
        let original = Decimal(engine: lot.originalQty) ?? remaining
        guard original != remaining else { return Humanize.shares(remaining, of: symbol) }
        return Humanize.shares(remaining, of: original, symbol: symbol)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 14) {
                ForEach(lot.buys) { buy in
                    PositionLotBuyLine(
                        buy: buy,
                        symbol: symbol,
                        who: who,
                        currentPrice: currentPrice,
                        post: post(buy),
                        openPost: openPost
                    )
                }
            }
            Button(L10n.string("Sell"), action: sell)
                .buttonStyle(PageButtonStyle(isProminent: true, horizontalPadding: 18))
                .accessibilityLabel(L10n.string("Sell %@ from %@", shares, who))
                .accessibilityIdentifier("accounts.lot.sell.\(lot.lotID)")
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
    }
}
