import DesktopCore
import SwiftUI

/// Everything about one order a trader would look up, as a key/value table: its type, size, how
/// much filled, its limit, what the market offered then, how it ended, and the broker's IDs.
struct OrderFactsView: View {
    let order: OrderActivity
    let account: String

    private func money(_ value: String?) -> String? {
        Decimal(engine: value)?.formatted(.currency(code: "USD"))
    }

    /// "Limit buy · day".
    private var kind: String {
        let side = L10n.string(order.side == "sell" ? "sell" : "buy")
        let type = L10n.string(order.orderType == "market" ? "Market %@" : "Limit %@", side)
        return L10n.string("%@ · day", type)
    }

    private var session: String? {
        switch order.session {
        case "regular": L10n.string("Regular hours")
        case "extended": L10n.string("Before or after regular hours")
        case "overnight": L10n.string("Overnight")
        default: nil
        }
    }

    /// "$200 of PM", or "$200 of PM · cut from $600" when the max per order trimmed it.
    private var size: String? {
        guard let planned = OrderAmount.planned(order) else { return nil }
        return ActivityCardOutcome.wasTrimmed(order)
            ? L10n.string("%@ · cut from %@", planned, Humanize.dollars(order.requestedUSD)) : planned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TechnicalSectionTitle(text: L10n.string("Order in %@", account))
            TechnicalFactRow(label: "Type") { Text(kind) }
            if let session {
                TechnicalFactRow(label: "Session") { Text(session) }
            }
            if let size {
                TechnicalFactRow(label: "Size") { Text(size) }
            }
            TechnicalFactRow(label: "Filled") {
                Text(Humanize.shares(Decimal(engine: order.filledQuantity) ?? 0, of: Decimal(engine: order.quantity) ?? 0))
            }
            if let limit = money(order.limitPrice) {
                TechnicalFactRow(label: "Limit") {
                    if let tolerance = Decimal(engine: order.entryTolerancePct), order.side != "sell" {
                        Text(L10n.string("%@ · %@%% above the guru", limit, tolerance.formatted()))
                    } else {
                        Text(limit)
                    }
                }
            }
            if money(order.quoteBid) != nil || money(order.quoteAsk) != nil {
                TechnicalFactRow(label: "Market then") {
                    Text(L10n.string("Bid %@ · Ask %@", money(order.quoteBid) ?? "—", money(order.quoteAsk) ?? "—"))
                }
            }
            if let fill = money(order.averageFillPrice) {
                TechnicalFactRow(label: "Average fill") { Text(fill) }
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
