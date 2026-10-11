import DesktopCore
import Foundation

/// What an order is worth, dollar first: what filled when anything did, otherwise what it was
/// sized to spend.
enum OrderAmount {
    /// Shares filled times their average price.
    static func filledUSD(_ order: OrderActivity) -> Decimal? {
        guard let filled = Decimal(engine: order.filledQuantity), filled > 0,
            let price = Decimal(engine: order.averageFillPrice)
        else { return nil }
        return filled * price
    }

    /// The order's budget, or its shares at its limit when the budget is not on record.
    static func plannedUSD(_ order: OrderActivity) -> Decimal? {
        if let budget = Decimal(engine: order.budgetUSD) { return budget }
        guard let quantity = Decimal(engine: order.quantity), let limit = Decimal(engine: order.limitPrice) else {
            return nil
        }
        return quantity * limit
    }

    /// "$199.82 of PM".
    @MainActor
    static func filled(_ order: OrderActivity) -> String? {
        filledUSD(order).map { Humanize.amount(Humanize.usd($0), of: order.symbol) }
    }

    /// "$200 of PM".
    @MainActor
    static func planned(_ order: OrderActivity) -> String? {
        plannedUSD(order).map { Humanize.amount(dollars($0), of: order.symbol) }
    }

    /// Whole dollars without cents ("$200"), otherwise to the cent ("$199.59").
    static func dollars(_ value: Decimal) -> String {
        var source = value
        var cents = Decimal()
        NSDecimalRound(&cents, &source, 2, .plain)
        return Humanize.dollars("\(cents)")
    }
}
