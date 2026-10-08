import DesktopCore
import Foundation

/// The one answer that settles a holdings question, worked out from what the broker holds now
/// and what CopyTrading bought. Copied shares the broker still holds stay copied; the rest of
/// the broker's shares count as the owner's own. A shortfall beside copied shares means some of
/// them were sold outside the app, oldest first, the way a sell takes them.
struct OwnershipFix: Equatable {
    let request: OwnershipResolutionRequest
    let title: String
    let explanation: String

    @MainActor
    init(incident: OwnershipIncidentView, position: AccountPositionView?, accountID: String) {
        let broker = Decimal(string: position?.brokerQty ?? "0") ?? 0
        let lots = position?.lots ?? []
        let copied = lots.reduce(Decimal(0)) { $0 + (Decimal(string: $1.remainingQty) ?? 0) }
        var remaining: [String: String] = [:]
        let external: Decimal
        if broker >= copied {
            external = broker - copied
            for lot in lots { remaining[lot.lotID] = lot.remainingQty }
            title =
                external == 0
                ? L10n.string("Clear the Old Count")
                : L10n.string("Count %@ Shares as Yours", Self.text(external))
            explanation = L10n.string(
                "CopyTrading counted %@ %@ shares, and the broker holds %@. Every copied share is still there, so the broker's other shares count as yours, and %@ is copied again.",
                Self.text(Decimal(string: incident.expectedQty) ?? 0), incident.symbol, Self.text(broker), incident.symbol)
        } else {
            external = 0
            var missing = copied - broker
            for lot in lots {
                let held = Decimal(string: lot.remainingQty) ?? 0
                let taken = min(held, missing)
                missing -= taken
                remaining[lot.lotID] = Self.text(held - taken)
            }
            title = L10n.string("Treat %@ Copied Shares as Sold", Self.text(copied - broker))
            explanation = L10n.string(
                "CopyTrading bought %@ %@ shares, and the broker holds %@. The missing shares were sold outside CopyTrading; the oldest buys are counted as sold first, and %@ is copied again.",
                Self.text(copied), incident.symbol, Self.text(broker), incident.symbol)
        }
        request = OwnershipResolutionRequest(
            resolutionID: "owner-\(incident.incidentID)", incidentID: incident.incidentID, accountID: accountID,
            symbol: incident.symbol, actor: "owner",
            reason: broker >= copied ? "owner_counted_broker_shares" : "owner_marked_copied_sold",
            brokerQty: Self.text(broker), externalQty: Self.text(external), lotRemaining: remaining)
    }

    private static func text(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
