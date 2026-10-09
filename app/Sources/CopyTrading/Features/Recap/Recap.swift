import DesktopCore
import Foundation

/// What happened while the owner was away: the copied orders that filled since they last looked,
/// how each account's balance moved, and how many calls wait for them now.
struct Recap: Identifiable, Equatable {
    struct Move: Equatable {
        let accountID: String
        let change: Decimal
    }

    let since: Date
    let fills: [FillWatch.Fill]
    let moves: [Move]
    let waiting: Int

    var id: Date { since }
    var isEmpty: Bool { fills.isEmpty && moves.allSatisfy { $0.change == 0 } && waiting == 0 }

    /// Built from what the app reads now and what it remembered when the owner last looked.
    @MainActor
    static func since(
        _ since: Date, activity: [SourceActivity], accounts: [AccountOverview], equities: [String: Decimal],
        waiting: Int
    ) -> Recap {
        var fills: [FillWatch.Fill] = []
        for post in activity {
            for destination in post.destinations {
                for order in destination.orders where order.status == "filled" {
                    guard let placed = Humanize.date(order.createdAt), placed > since else { continue }
                    fills.append(
                        FillWatch.Fill(
                            clientID: order.clientID, side: order.side, symbol: order.symbol,
                            shares: Decimal(string: order.filledQuantity) ?? 0,
                            price: order.averageFillPrice.flatMap { Decimal(string: $0) },
                            accountID: destination.accountID, guruID: post.guruID))
                }
            }
        }
        let moves = accounts.filter(\.activeConfiguration).compactMap { account -> Move? in
            guard let before = equities[account.accountID], let now = Decimal(engine: account.balance?.equity) else {
                return nil
            }
            return Move(accountID: account.accountID, change: now - before)
        }
        return Recap(since: since, fills: fills, moves: moves, waiting: waiting)
    }
}
