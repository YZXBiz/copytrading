import DesktopCore
import Foundation

/// A stock CopyTrading bought and still holds in the chosen accounts: what a hand-entered sell can
/// pick from. Shares held outside CopyTrading are never sold by it, so they are left out.
struct ManualHolding: Identifiable, Equatable {
    let symbol: String
    /// CopyTrading's shares across the chosen accounts.
    let shares: Decimal
    /// The broker's last price; nil when the broker was not read.
    let price: Decimal?
    /// The prices the guru bought at, from the posts that opened each buy, oldest first.
    let buyPrices: [Decimal]

    var id: String { symbol }
    var value: Decimal? { price.map { $0 * shares } }

    /// The stocks held in `accountIDs` (every account when none is chosen), by symbol.
    static func holdings(in accounts: [AccountOverview], accountIDs: Set<String>) -> [ManualHolding] {
        let chosen = accountIDs.isEmpty ? accounts : accounts.filter { accountIDs.contains($0.accountID) }
        var bySymbol: [String: ManualHolding] = [:]
        for position in chosen.flatMap(\.positions) {
            guard let owned = Decimal(string: position.ownedQty), owned > 0 else { continue }
            let symbol = position.symbol.uppercased()
            let existing = bySymbol[symbol]
            var prices = existing?.buyPrices ?? []
            for lot in position.lots {
                guard let remaining = Decimal(string: lot.remainingQty), remaining > 0,
                    let price = lot.excerpt.flatMap(ManualInstructionGuess.price(in:)), !prices.contains(price)
                else { continue }
                prices.append(price)
            }
            bySymbol[symbol] = ManualHolding(
                symbol: symbol,
                shares: (existing?.shares ?? 0) + owned,
                price: existing?.price ?? position.currentPrice.flatMap { Decimal(string: $0) },
                buyPrices: prices
            )
        }
        return bySymbol.values.sorted { ($0.value ?? 0) == ($1.value ?? 0) ? $0.symbol < $1.symbol : ($0.value ?? 0) > ($1.value ?? 0) }
    }
}
