import DesktopCore
import Foundation

/// Which copied orders were newly sent to the broker or newly filled since the last read, so the app
/// can say each once. An order counts only if it was sent or filled after the app opened, so a
/// restart never re-announces the day, and nothing that happened since is ever swallowed.
struct FillWatch {
    /// One order, with who it was copied from and where; the owner's own sale names no guru.
    struct Fill: Equatable {
        let clientID: String
        let side: String
        let symbol: String
        let shares: Decimal
        let price: Decimal?
        let accountID: String
        let guruID: String?
        var byOwner = false
    }

    /// What one read found: orders that went out, and orders that filled.
    struct News: Equatable {
        var sent: [Fill] = []
        var filled: [Fill] = []
        var isEmpty: Bool { sent.isEmpty && filled.isEmpty }
    }

    /// Statuses of an order the broker has taken and is working; "prepared" has not gone out yet.
    static let working: Set<String> = [
        "accepted", "pending_new", "accepted_for_bidding", "new", "partially_filled", "held",
    ]

    /// An order that is done and bought or sold shares: filled, or partly filled before it was
    /// cancelled or expired.
    static func ended(withFills order: OrderActivity) -> Bool {
        order.status != "prepared" && !working.contains(order.status)
            && (Decimal(string: order.filledQuantity) ?? 0) > 0
    }

    private let openedAt: Date
    private var sent: Set<String> = []
    private var filled: Set<String> = []

    init(openedAt: Date = .now) {
        self.openedAt = openedAt
    }

    /// The orders sent and filled since the last read. An order that went out and filled between two
    /// reads is said once, as its fill.
    mutating func news(in activity: [SourceActivity]) -> News {
        var news = News()
        for post in activity {
            for destination in post.destinations {
                for order in destination.orders {
                    if Self.ended(withFills: order) {
                        guard filled.insert(order.clientID).inserted else { continue }
                        sent.insert(order.clientID)
                        guard isSince(order.endedAt ?? order.submittedAt) else { continue }
                        news.filled.append(
                            fill(order, shares: order.filledQuantity, price: order.averageFillPrice, in: destination, post))
                    } else if Self.working.contains(order.status) {
                        guard sent.insert(order.clientID).inserted, isSince(order.submittedAt) else {
                            continue
                        }
                        news.sent.append(fill(order, shares: order.quantity, price: order.limitPrice, in: destination, post))
                    }
                }
            }
        }
        return news
    }

    private func isSince(_ stamp: String?) -> Bool {
        guard let stamp, let date = Self.date(stamp) else { return false }
        return date >= openedAt
    }

    private func fill(
        _ order: OrderActivity, shares: String, price: String?, in destination: DestinationActivity, _ post: SourceActivity
    ) -> Fill {
        Self.fill(order, shares: shares, price: price, accountID: destination.accountID, guruID: post.guruID)
    }

    static func fill(_ order: OrderActivity, shares: String, price: String?, accountID: String, guruID: String?) -> Fill {
        Fill(
            clientID: order.clientID, side: order.side, symbol: order.symbol,
            shares: Decimal(string: shares) ?? 0, price: price.flatMap { Decimal(string: $0) },
            accountID: accountID, guruID: order.isOwnerSale ? nil : guruID, byOwner: order.isOwnerSale)
    }

    private static func date(_ stamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
    }
}
