import DesktopCore
import SwiftUI

/// Asks the owner to approve or reject one agent request; approving needs Touch ID.
struct AgentProposalSheet: View {
    let model: AppModel
    let proposal: AgentProposal
    @State private var isDeciding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(proposal.approvalHeading, systemImage: "hand.raised")
                .font(.title3.bold())
            Text(proposal.summary)
                .font(.title2)
            if let environment = proposal.environment {
                LabeledContent(L10n.string("Account")) { EnvironmentBadge(environment: environment) }
            }
            LabeledContent(L10n.string("Requested by"), value: proposal.requester)
            LabeledContent(L10n.string("Expires"), value: Humanize.timestamp(proposal.expiresAt))
            Callout(
                L10n.string(
                    "Approve only if you asked for this. Agents read messages written by other people, so a request can come from text you have never seen."
                ),
                tone: .caution
            )
            HStack {
                Spacer()
                Button(L10n.string("Reject"), role: .destructive) { decide(approve: false) }
                    .disabled(isDeciding)
                Button(L10n.string("Approve…")) { decide(approve: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isDeciding)
            }
        }
        .padding(24)
        .frame(width: 440)
        .interactiveDismissDisabled()
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
