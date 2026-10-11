import Foundation

/// An order's limit beside the price it met, for the price ruler on the Activity card.
struct PricePoints: Equatable {
    let limit: Decimal
    /// What the order met: the fill price, or the ask (a buy) or bid (a sell) when it went out.
    let market: Decimal
    let marketLabel: String
    let buying: Bool
}
