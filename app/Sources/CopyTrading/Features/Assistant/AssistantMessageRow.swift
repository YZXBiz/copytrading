import DesktopCore
import SwiftUI

/// One turn of the conversation. The owner's question is a soft bubble at the trailing edge; the
/// answer is plain text at the leading edge, with what was looked at, approvals, and links.
struct AssistantMessageRow: View {
    let message: AssistantMessage
    /// The last answer while the engine is still writing it.
    let isWriting: Bool
    let model: AppModel
    let follow: (AssistantLink) -> Void

    var body: some View {
        switch message.author {
        case .owner: question
        case .assistant: answer
        }
    }

    private var question: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 56)
            Text(message.text)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Palette.well, in: .rect(cornerRadius: 17, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("You asked: %@", message.text))
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !message.steps.isEmpty || isWorking {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(message.steps.enumerated()), id: \.offset) { _, step in
                        AssistantStepLine(text: step)
                    }
                    if isWorking {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityHidden(true)
                            Text(L10n.string(message.steps.isEmpty ? "Looking into it…" : "Still looking…"))
                                .font(DesignTokens.caption)
                                .foregroundStyle(Palette.tertiaryInk)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !message.text.isEmpty {
                Text(AssistantMarkdown.rendered(message.text))
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(message.proposalIDs, id: \.self) { id in
                AssistantProposalCard(model: model, proposalID: id)
            }
            if !links.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { linkButtons }
                    VStack(alignment: .leading, spacing: 6) { linkButtons }
                }
            }
            if let error = message.errorText {
                Label {
                    Text(AssistantEngineText.localized(error))
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(StatusTone.caution.color)
                }
                .font(DesignTokens.caption)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StatusTone.caution.color.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("assistant.error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var isWorking: Bool { isWriting && message.text.isEmpty && message.errorText == nil }

    /// Each place once, however often the assistant pointed at it.
    private var links: [AssistantLink] {
        message.links.reduce(into: []) { kept, link in
            if !kept.contains(where: { $0.kind == link.kind && $0.id == link.id }) { kept.append(link) }
        }
    }

    private var linkButtons: some View {
        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
            Button {
                follow(link)
            } label: {
                InlineActionMark(title: title(for: link))
            }
            .buttonStyle(QuietPressButtonStyle())
            .accessibilityIdentifier("assistant.link.\(link.kind)")
        }
    }

    private func title(for link: AssistantLink) -> String {
        switch link.kind {
        case "account": L10n.string("%@ in Accounts", link.title)
        case "guru":
            L10n.string("%@ in People", GuruDirectory(model.savedTradingConfiguration).name(for: link.id) ?? link.title)
        default: L10n.string(link.title)
        }
    }
}
