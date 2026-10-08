import DesktopCore
import SwiftUI

/// A stock whose holdings don't add up: what CopyTrading counted, what the broker holds, and the
/// one answer that settles it. Until then every call for the stock waits.
struct OwnershipIncidentCallout: View {
    let incident: OwnershipIncidentView
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel
    @State private var isConfirming = false

    private var fix: OwnershipFix {
        OwnershipFix(
            incident: incident, position: account.positions.first { $0.symbol == incident.symbol },
            accountID: account.accountID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Callout(
                L10n.string(
                    "%@ holdings need your review: CopyTrading counted %@, the broker holds %@. Calls for %@ wait until you settle it.",
                    incident.symbol, incident.expectedQty, incident.actualQty, incident.symbol),
                tone: .caution)
            Button(fix.title) { isConfirming = true }
                .controlSize(.small)
                .disabled(feature.pendingAccounts.contains(account.accountID))
                .accessibilityIdentifier("accounts.ownership.\(incident.symbol)")
                .confirmationDialog(fix.title, isPresented: $isConfirming, titleVisibility: .visible) {
                    Button(fix.title, action: settle)
                    Button(L10n.string("Cancel"), role: .cancel) {}
                } message: {
                    Text(fix.explanation)
                }
        }
    }

    private func settle() {
        Task { await feature.resolveOwnership(fix, using: model.accountActions()) }
    }
}
