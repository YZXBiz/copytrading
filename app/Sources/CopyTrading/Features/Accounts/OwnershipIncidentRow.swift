import DesktopCore
import SwiftUI

/// A stock whose holdings don't add up, as one attention row: what doesn't add up, what waits on
/// it, and the owner's one answer. The answer opens a line in the row saying what it does before
/// anything is sent; no system dialog. While an order the app didn't place is open at the broker,
/// the engine can't settle holdings, so the row says what has to happen first instead.
struct OwnershipIncidentRow: View {
    let incident: OwnershipIncidentView
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel
    @State private var isConfirming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fix: OwnershipFix {
        OwnershipFix(
            incident: incident, position: account.positions.first { $0.symbol == incident.symbol },
            accountID: account.accountID)
    }

    /// An order at the broker the app can't account for; the engine refuses to settle until it is gone.
    private var isBlocked: Bool {
        AccountWarnings.shown(account.accountActivityReason) != nil
    }

    private var isSending: Bool { feature.pendingAccounts.contains(account.accountID) }

    var body: some View {
        AttentionRow(headline: fix.headline, detail: fix.detail) {
            if isBlocked {
                Text(L10n.string("First, the open order in Alpaca has to fill or be cancelled."))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            } else if isConfirming {
                VStack(alignment: .leading, spacing: 10) {
                    Text(fix.confirmation)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Button(fix.confirm, action: settle)
                            .buttonStyle(PageButtonStyle(isProminent: true))
                            .disabled(isSending)
                            .accessibilityIdentifier("accounts.ownership.confirm.\(incident.symbol)")
                        Button(L10n.string("Not Now")) { isConfirming = false }
                            .buttonStyle(QuietTextButtonStyle())
                        if isSending {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .transition(.opacity)
            } else {
                Button(fix.action) { isConfirming = true }
                    .buttonStyle(QuietTextButtonStyle())
                    .disabled(isSending)
                    .accessibilityIdentifier("accounts.ownership.\(incident.symbol)")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isConfirming)
    }

    private func settle() {
        Task {
            await feature.resolveOwnership(fix, using: model.accountActions())
            isConfirming = false
        }
    }
}
