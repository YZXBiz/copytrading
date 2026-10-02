import DesktopCore
import SwiftUI

/// Something the assistant asked the owner to approve, on a small white slip in the answer. The
/// assistant never approves; Review… brings back the approval sheet, which asks for Touch ID.
struct AssistantProposalCard: View {
    let model: AppModel
    let proposalID: String
    @State private var isReviewing = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var proposal: AgentProposal? { model.agentProposals.first { $0.id == proposalID } }

    /// Waiting while the engine still lists it as pending, or before the list has loaded it.
    private var isWaiting: Bool { proposal.map { $0.state == .pending } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isWaiting ? "hand.raised.fill" : statusSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isWaiting ? StatusTone.caution.color : Palette.tertiaryInk)
                    .accessibilityHidden(true)
                Text(status)
                    .font(DesignTokens.caption.weight(.medium))
                    .foregroundStyle(Palette.secondaryInk)
            }
            Text(question)
                .font(DesignTokens.cardSerif)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if isWaiting {
                HStack(spacing: 10) {
                    Button(action: review) {
                        // Reads "Review…" in English; its own key, as Chinese says it differently from Setup's "Review…".
                        Text(L10n.string("Review the approval…"))
                            .font(DesignTokens.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Palette.accent, in: .capsule)
                    }
                    .buttonStyle(QuietPressButtonStyle())
                    .disabled(isReviewing)
                    .accessibilityHint(L10n.string("Opens the approval sheet"))
                    .accessibilityIdentifier("assistant.review")
                    Text(L10n.string("Approving asks for Touch ID."))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.page, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("%@: %@", status, question))
    }

    private var question: String {
        guard let proposal else { return L10n.string("A change that needs your approval") }
        return isWaiting ? L10n.string("%@?", proposal.summary) : proposal.summary
    }

    private var status: String {
        guard let proposal else { return L10n.string("Waiting for your approval") }
        switch proposal.state {
        case .pending: return L10n.string("Waiting for your approval")
        case .running: return L10n.string("Approved, working on it")
        case .succeeded: return L10n.string("Approved and done")
        case .rejected: return L10n.string("You turned this down")
        case .expired: return L10n.string("Expired before approval")
        case .failed, .outcomeUnknown, .discarded: return L10n.string(Humanize.code(proposal.state.rawValue))
        }
    }

    private var statusSymbol: String {
        switch proposal?.state {
        case .succeeded, .running: "checkmark.circle.fill"
        default: "minus.circle"
        }
    }

    private func review() {
        isReviewing = true
        Task {
            await model.refreshAssistantProposals()
            isReviewing = false
        }
    }
}
