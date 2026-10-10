import DesktopCore
import Foundation

/// "In stocks" counts every share at the broker, the owner's own included. The split says how much
/// of it CopyTrading copied and how much the owner holds outside it, so a sale that empties the
/// copied part reads as such even while the meter stays high.
enum ExposureSplit {
    /// Each position's market value shared by its copied and outside shares; nil without values.
    static func dollars(_ account: AccountOverview) -> (copied: Decimal, outside: Decimal)? {
        var copied = Decimal(0)
        var outside = Decimal(0)
        var valued = false
        for position in account.positions {
            guard let value = Decimal(engine: position.marketValue) else { continue }
            let owned = Decimal(engine: position.ownedQty) ?? 0
            let external = Decimal(engine: position.externalQty) ?? 0
            let held = Decimal(engine: position.brokerQty) ?? owned + external
            guard held > 0 else { continue }
            valued = true
            let copiedShare = min(owned, held) / held
            copied += value * copiedShare
            outside += value * (1 - copiedShare)
        }
        return valued ? (copied, outside) : nil
    }

    /// "$0 copied · $2,086 held outside CopyTrading", only when the owner holds shares themselves.
    @MainActor
    static func note(_ account: AccountOverview?) -> String? {
        guard let account, let split = dollars(account), split.outside >= 1 else { return nil }
        let money = Decimal.FormatStyle.Currency(code: "USD").precision(.fractionLength(0))
        return L10n.string("%@ copied · %@ held outside CopyTrading", split.copied.formatted(money), split.outside.formatted(money))
    }
}
