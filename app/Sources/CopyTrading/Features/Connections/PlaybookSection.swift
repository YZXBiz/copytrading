import DesktopCore
import SwiftUI

/// How the model should read this guru: learned from the channel, then edited by the owner.
struct PlaybookSection: View {
    @Binding var route: TradingRouteDraft
    let learn: (TradingRouteDraft) async throws -> LearnedGuruPlaybook
    @State private var isLearning = false
    @State private var learned: LearnedGuruPlaybook?
    /// How many of the learned examples were new to this guru.
    @State private var addedExamples = 0
    @State private var failure: String?
    @FocusState private var isEditing: Bool

    var body: some View {
        SheetSection(L10n.string("Playbook")) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button(action: start) {
                    Label(
                        L10n.string(route.playbook.trimmedLines.isEmpty ? "Learn from Channel" : "Learn Again"),
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(SheetQuietButtonStyle())
                .disabled(isLearning)
                .accessibilityIdentifier("playbook.learn")
                if isLearning {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("Reading recent posts…"))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            if let learned {
                Callout(learnedSummary(learned), tone: .positive)
                    .accessibilityIdentifier("playbook.summary")
            }
            if let failure {
                Callout(failure, tone: .critical)
                    .accessibilityIdentifier("playbook.failure")
            }
            // In a soft well, like every field in the sheet, tall enough to read several lines.
            TextEditor(text: $route.playbook)
                .font(DesignTokens.bodyText)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .focused($isEditing)
                .padding(8)
                .background(Palette.well, in: .rect(cornerRadius: 8))
                .accessibilityLabel(L10n.string("Playbook"))
                .accessibilityIdentifier("playbook.text")
            Text(L10n.string("%@ of %@ characters", route.playbook.count.formatted(), tradingPlaybookMaxLength.formatted()))
                .font(DesignTokens.caption)
                .foregroundStyle(route.playbook.count > tradingPlaybookMaxLength ? Palette.loss : Palette.tertiaryInk)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)
        } footer: {
            Text(
                L10n.string(
                    "How this guru writes buys, sells, and tickers, one rule per line. Learn drafts it from recent posts; edit anything. Name a company's ticker on its own line, such as “%@ means %@”.",
                    "英伟达", "NVDA"
                )
            )
        }
        .icon(symbol: "text.book.closed")
        .mark(route.playbook.trimmedLines.isEmpty ? .needsYou : .done)
    }

    /// What Learn did, truthfully: the playbook is drafted, and examples are named only when some
    /// were added beside the owner's own.
    @MainActor
    private func learnedSummary(_ learned: LearnedGuruPlaybook) -> String {
        var sentences = [
            L10n.string("Read %lld posts with %@.", Int64(learned.postsRead), learned.model),
            learned.summary,
            L10n.string("The playbook is drafted; read it over before you start copying."),
        ]
        if addedExamples == 1 {
            sentences.append(L10n.string("Added 1 example post below yours."))
        } else if addedExamples > 1 {
            sentences.append(L10n.string("Added %lld example posts below yours.", Int64(addedExamples)))
        }
        return L10n.sentences(sentences.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    private func start() {
        isLearning = true
        failure = nil
        Task {
            defer { isLearning = false }
            do {
                let result = try await learn(route)
                route.playbook = result.playbook
                addedExamples = route.addLearnedExamples(result.examples)
                learned = result
            } catch {
                learned = nil
                failure = AppModel.userMessage(for: error)
            }
        }
    }
}
