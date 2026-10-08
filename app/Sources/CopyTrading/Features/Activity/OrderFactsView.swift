import DesktopCore
import SwiftUI

/// Everything about one order a trader would look up: how it went out, at what limit, what the
/// market offered then, the broker's IDs, and how it ended.
struct OrderFactsView: View {
    let order: OrderActivity
    let account: String

    private func money(_ value: String?) -> String? {
        Decimal(engine: value)?.formatted(.currency(code: "USD"))
    }

    private var kind: String {
        let side = L10n.string(order.side == "sell" ? "Sell" : "Buy")
        let type = L10n.string(order.orderType == "market" ? "market order" : "limit order")
        return L10n.string("%@ %@ %@, good for the day", side, order.symbol, type)
    }

    private var session: String? {
        switch order.session {
        case "regular": L10n.string("Regular hours")
        case "extended": L10n.string("Before or after regular hours")
        case "overnight": L10n.string("Overnight")
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Order in %@", account))
                .font(DesignTokens.caption.weight(.medium))
                .foregroundStyle(Palette.secondaryInk)
            TechnicalFactRow(label: "Order") { Text(kind) }
            if let session {
                TechnicalFactRow(label: "Session") { Text(session) }
            }
            TechnicalFactRow(label: "Shares") {
                Text(L10n.string("%@ filled of %@", order.filledQuantity, order.quantity)).monospacedDigit()
            }
            if let limit = money(order.limitPrice) {
                TechnicalFactRow(label: "Limit") {
                    if let guru = money(order.sourcePrice), let tolerance = Decimal(engine: order.entryTolerancePct) {
                        Text(L10n.string("%@ (guru's price %@, up to %@%% above)", limit, guru, tolerance.formatted()))
                    } else {
                        Text(limit)
                    }
                }
            }
            if money(order.quoteBid) != nil || money(order.quoteAsk) != nil {
                TechnicalFactRow(label: "Market then") {
                    Text(L10n.string("bid %@ · ask %@", money(order.quoteBid) ?? "—", money(order.quoteAsk) ?? "—"))
                        .monospacedDigit()
                }
            }
            if let fill = money(order.averageFillPrice) {
                TechnicalFactRow(label: "Average fill") { Text(fill).monospacedDigit() }
            }
            if let why = CancelReasonText.sentence(order) {
                TechnicalFactRow(label: "Why it ended") {
                    Text(why).fixedSize(horizontal: false, vertical: true)
                }
            }
            CopyableIdentifierRow(label: "Order ID", value: order.clientID)
            if let brokerID = order.brokerID {
                CopyableIdentifierRow(label: "Alpaca ID", value: brokerID)
            }
        }
    }
}
