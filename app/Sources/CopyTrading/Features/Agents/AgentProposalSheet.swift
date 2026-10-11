import DesktopCore
import SwiftUI

/// Asks the owner to approve or reject one agent request; approving needs Touch ID.
struct AgentProposalSheet: View {
    let model: AppModel
    let proposal: AgentProposal
    @State private var isDeciding = false

    var body: some View {
        SheetScaffold(
            kind: L10n.string("Agent request"), title: proposal.summary, lede: proposal.approvalHeading, scrolls: false
        ) {
            SheetSection(L10n.string("The request")) {
                if let environment = proposal.environment {
                    SheetRow(title: L10n.string("Account")) { EnvironmentBadge(environment: environment) }
                }
                SheetRow(title: L10n.string("Requested by")) { value(proposal.requester) }
                SheetRow(title: L10n.string("Expires")) { value(Humanize.timestamp(proposal.expiresAt)) }
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
