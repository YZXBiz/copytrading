import DesktopCore
import SwiftUI

struct AccountWarnings: View {
    let account: AccountOverview

    var body: some View {
        if let reason = account.accountRiskReason {
            Callout(L10n.string("Risk valuation: %@", L10n.string(Humanize.code(reason))), tone: .caution)
        }
        if let reason = account.accountActivityReason {
            Callout(L10n.string("Broker activity: %@", L10n.string(Humanize.code(reason))), tone: .caution)
        }
        ForEach(account.ownershipIncidents) { incident in
            Callout(
                L10n.string(
                    "%@ ownership mismatch: expected %@, broker reports %@ (%@, %@).",
                    incident.symbol, incident.expectedQty, incident.actualQty,
                    L10n.string(Humanize.code(incident.cause).lowercased()), Humanize.timestamp(incident.observedAt)
                ),
                tone: .critical
            )
        }
        let listed = Set(account.ownershipIncidents.map(\.incidentID))
        let unlisted = account.unresolvedIncidents.filter { !listed.contains($0) }
        if !unlisted.isEmpty {
            Callout(L10n.string("Unresolved incidents: %@", Humanize.joined(unlisted)), tone: .critical)
        }
    }
}
