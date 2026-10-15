import DesktopCore
import Foundation

/// One choice in a buy's How much row: the usual sizes that spend the same dollars in the chosen
/// account, because the max per order cuts them all to it, read as one ("¼ or more $250").
struct BuySize: Equatable {
    /// The shares of the full position it stands for, smallest first; "" is the full position.
    let shares: [String]
    /// What it spends in the one chosen account after the max per order; nil when several are
    /// chosen.
    let usd: Decimal?
    /// The max per order cut it.
    let isCapped: Bool

    /// The usual sizes, smallest first, with those the max per order makes identical merged.
    static func choices(
        _ shares: [String] = ManualInstructionDraft.buySizes, fullPosition: TradingRouteConnection?, maxOrderUSD: Decimal?
    ) -> [BuySize] {
        var sizes: [BuySize] = []
        for share in shares {
            let fraction = share.isEmpty ? nil : Decimal(string: share)
            let asked = fullPosition?.copiedBudgetUSD(sourceFraction: fraction)
            let usd = fullPosition?.spentUSD(sourceFraction: fraction, maxOrderUSD: maxOrderUSD)
            let isCapped = asked.flatMap { asked in usd.map { asked > $0 } } ?? false
            // ¼ of $1,000 is exactly a $250 max, so the cut ⅓ and up join it.
            if let last = sizes.last, isCapped, last.usd == usd {
                sizes[sizes.count - 1] = BuySize(shares: last.shares + [share], usd: usd, isCapped: true)
            } else {
                sizes.append(BuySize(shares: [share], usd: usd, isCapped: isCapped))
            }
        }
        return sizes
    }

    /// Whether a draft's share is one this choice stands for.
    func contains(_ share: String) -> Bool {
        shares.contains { $0.isEmpty ? share.trimmed.isEmpty : ManualInstructionDraft.sameShare($0, share) }
    }
}
