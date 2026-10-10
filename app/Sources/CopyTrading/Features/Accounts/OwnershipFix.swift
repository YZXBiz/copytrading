import DesktopCore
import Foundation

/// The one answer that settles a holdings question, worked out from what the broker holds now
/// and what CopyTrading bought. Copied shares the broker still holds stay copied; the rest of
/// the broker's shares count as the owner's own. A shortfall beside copied shares means some of
/// them were sold outside the app, oldest first, the way a sell takes them.
struct OwnershipFix: Equatable {
    let request: OwnershipResolutionRequest
    /// What doesn't add up, as one plain sentence: "28.011 shares of NIO CopyTrading didn't buy".
    let headline: String
    /// What waits on the owner until it is settled.
    let detail: String
    /// The owner's answer, as a short word on the row: "They're Mine".
    let action: String
    /// What the answer does, shown in the row before it is sent.
    let confirmation: String
    /// The one black button that sends it.
    let confirm: String

    @MainActor
    init(incident: OwnershipIncidentView, position: AccountPositionView?, accountID: String) {
        let symbol = incident.symbol
        let broker = Decimal(string: position?.brokerQty ?? "0") ?? 0
        let lots = position?.lots ?? []
        let copied = lots.reduce(Decimal(0)) { $0 + (Decimal(string: $1.remainingQty) ?? 0) }
        var remaining: [String: String] = [:]
        let external: Decimal
        if broker >= copied {
            external = broker - copied
            for lot in lots { remaining[lot.lotID] = lot.remainingQty }
            if external == 0 {
                headline = L10n.string("CopyTrading's count of %@ is out of date", symbol)
                detail = L10n.string(
                    "It counted %@; the broker holds %@. %@ calls wait until you update it.",
                    Humanize.shares(Decimal(string: incident.expectedQty) ?? 0), Humanize.shares(broker), symbol)
                action = L10n.string("Update the Count")
                confirmation = L10n.string("CopyTrading will use the broker's count. Nothing is bought or sold.")
                confirm = L10n.string("Update the Count")
            } else {
                headline = L10n.string("%@ of %@ that CopyTrading didn't buy", Humanize.shares(external), symbol)
                detail = L10n.string("%@ calls wait until you say whose they are.", symbol)
                action = L10n.string("They're Mine")
                confirmation = L10n.string(
                    "CopyTrading will leave these shares alone and copy %@ calls again. Nothing is bought or sold.", symbol)
                confirm = L10n.string("Count as Mine")
            }
        } else {
            external = 0
            var missing = copied - broker
            for lot in lots {
                let held = Decimal(string: lot.remainingQty) ?? 0
                let taken = min(held, missing)
                missing -= taken
                remaining[lot.lotID] = Self.text(held - taken)
            }
            headline = L10n.string("Fewer %@ shares at the broker than CopyTrading copied", symbol)
            detail = L10n.string(
                "%@ are missing, likely sold outside CopyTrading. %@ calls wait until you confirm.",
                Humanize.shares(copied - broker), symbol)
            action = L10n.string("They Were Sold")
            confirmation = L10n.string(
                "CopyTrading will count its oldest copied shares as sold first and copy %@ calls again. Nothing is bought or sold.",
                symbol)
            confirm = L10n.string("Count as Sold")
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
