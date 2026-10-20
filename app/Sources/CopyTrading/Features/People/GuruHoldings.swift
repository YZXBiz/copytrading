import DesktopCore
import Foundation

/// What the owner holds from one guru's calls, in the accounts the setup copies into. An account
/// removed from the setup keeps its shares at the broker, but CopyTrading no longer tracks them, so
/// they never count here.
struct GuruHoldings: Equatable {
    /// What the held shares cost.
    let cost: Decimal
    /// How they stand today, up or down.
    let gain: Decimal
    let stocks: Int

    /// Nil while nothing from this guru is held in a set-up account.
    init?(guruID: String, accounts: [AccountOverview], setUpAccountIDs: Set<String>) {
        let lots = accounts.filter { setUpAccountIDs.contains($0.accountID) }.flatMap { account in
            account.positions.flatMap { position in
                position.lots.filter { $0.guruID == guruID && (Decimal(engine: $0.remainingQty) ?? 0) > 0 }
                    .map { (lot: $0, symbol: position.symbol) }
            }
        }
        guard !lots.isEmpty else { return nil }
        cost = lots.reduce(Decimal(0)) {
            $0 + (Decimal(engine: $1.lot.remainingQty) ?? 0) * (Decimal(engine: $1.lot.averagePrice) ?? 0)
        }
        gain = lots.compactMap { Decimal(engine: $0.lot.unrealizedPL) }.reduce(0, +)
        stocks = Set(lots.map(\.symbol)).count
    }
}
