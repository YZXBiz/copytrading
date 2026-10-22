import DesktopCore
import SwiftUI

/// Asks the owner to approve or reject one agent request; approving needs Touch ID.
struct AgentProposalSheet: View {
    let model: AppModel
    let proposal: AgentProposal
    @State private var isDeciding = false

    var body: some View {
        SheetScaffold(
            title: proposal.sheetTitle, lede: proposal.approvalHeading, scrolls: false
        ) {
            SheetSection(L10n.string("Agent request")) {
                SheetGroup {
                    if let accountID = proposal.accountID {
                        // The account by name and its mode in words; only Live carries colour.
                        SheetRow(title: L10n.string("Account"), isReading: true) {
                            let environment = model.environment(of: proposal)
                            HStack(spacing: 6) {
                                value(accountID)
                                if let environment {
                                    Text(verbatim: "·").foregroundStyle(Palette.tertiaryInk).accessibilityHidden(true)
                                    Text(L10n.string(environment == .live ? "Live" : "Paper"))
                                        .font(DesignTokens.bodyText)
                                        .foregroundStyle(environment == .live ? Color.orange : Palette.secondaryInk)
                                }
                            }
                        }
                    }
                    ForEach(Array(model.limitRows(of: proposal).enumerated()), id: \.offset) { _, row in
                        SheetRow(title: row.title, isReading: true) {
                            value(L10n.string("%@ → %@", row.now, row.after))
                        }
                    }
                    SheetRow(title: L10n.string("Requested by"), isReading: true) { value(proposal.requester) }
                    SheetRow(title: L10n.string("Expires"), isReading: true) { value(Humanize.timestamp(proposal.expiresAt)) }
                }
            }
            Callout(
                L10n.string(
                    "Approve only if you asked for this. Agents read messages written by other people, so a request can come from text you have never seen."
                ),
                tone: .caution
            )
        } actions: {
            Button(L10n.string("Reject"), role: .destructive) { decide(approve: false) }
                .buttonStyle(SheetButtonStyle())
                .disabled(isDeciding)
            Button(L10n.string("Approve…")) { decide(approve: true) }
                .buttonStyle(SheetButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(isDeciding)
        }
        .frame(width: 500)
        .interactiveDismissDisabled()
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.bodyText)
            .foregroundStyle(Palette.secondaryInk)
            .multilineTextAlignment(.trailing)
    }

    private func decide(approve: Bool) {
        isDeciding = true
        Task {
            if approve {
                await model.approveAgentProposal(proposal)
            } else {
                await model.rejectAgentProposal(proposal)
            }
            isDeciding = false
        }
    }
}
