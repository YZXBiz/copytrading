import DesktopCore
import SwiftUI

/// What needs the owner's eye about the account itself. A check that simply hasn't run yet, as
/// while copying is off, is not a warning and stays out of sight.
struct AccountWarnings: View {
    /// A reason worth showing: anything but "not checked yet".
    static func shown(_ reason: String?) -> String? {
        reason == "not_checked" ? nil : reason
    }

    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel

    var body: some View {
        if let reason = Self.shown(account.accountRiskReason) {
            Callout(L10n.string("Risk valuation: %@", L10n.string(Humanize.code(reason))), tone: .caution)
        }
        if let reason = Self.shown(account.accountActivityReason) {
            Callout(L10n.string("Broker activity: %@", L10n.string(Humanize.code(reason))), tone: .caution)
        }
        ForEach(account.ownershipIncidents) { incident in
            OwnershipIncidentCallout(incident: incident, account: account, model: model, feature: feature)
        }
        let listed = Set(account.ownershipIncidents.map(\.incidentID))
        let unlisted = account.unresolvedIncidents.filter { !listed.contains($0) }
        if !unlisted.isEmpty {
            Callout(L10n.string("Unresolved incidents: %@", Humanize.joined(unlisted)), tone: .critical)
        }
    }
}
