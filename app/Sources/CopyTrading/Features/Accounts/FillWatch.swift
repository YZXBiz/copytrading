import DesktopCore
import Foundation

/// Which copied orders have newly filled since the last read, so the app can say so once. The
/// first read only learns what is already filled; nothing from before the app opened is announced.
struct FillWatch {
    /// One order that filled, with who it was copied from and where.
    struct Fill: Equatable {
        let clientID: String
        let side: String
        let symbol: String
        let shares: Decimal
        let price: Decimal?
        let accountID: String
        let guruID: String?
    }

    private var seen: Set<String> = []
    private var primed = false

    /// The fills that are new in this read.
    mutating func newFills(in activity: [SourceActivity]) -> [Fill] {
        var fills: [Fill] = []
        for post in activity {
            for destination in post.destinations {
                for order in destination.orders where order.status == "filled" && !seen.contains(order.clientID) {
                    seen.insert(order.clientID)
                    fills.append(
                        Fill(
                            clientID: order.clientID, side: order.side, symbol: order.symbol,
                            shares: Decimal(string: order.filledQuantity) ?? 0,
                            price: order.averageFillPrice.flatMap { Decimal(string: $0) },
                            accountID: destination.accountID, guruID: post.guruID))
                }
            }
        }
        defer { primed = true }
        return primed ? fills : []
    }
}
