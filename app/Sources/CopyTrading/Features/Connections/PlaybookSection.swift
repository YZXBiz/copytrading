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
            // No box: the text on one light rule, like every field in the sheet.
            TextEditor(text: $route.playbook)
                .font(DesignTokens.bodyText)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) { Hairline() }
                .accessibilityLabel(L10n.string("Playbook"))
                .accessibilityIdentifier("playbook.text")
            Text(L10n.string("%@ of %@ characters", route.playbook.count.formatted(), tradingPlaybookMaxLength.formatted()))
                .font(DesignTokens.caption)
                .foregroundStyle(route.playbook.count > tradingPlaybookMaxLength ? .red : Palette.tertiaryInk)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)
        } footer: {
            Text(
                L10n.string(
                    "Learn reads the channel's recent posts and drafts how this guru writes buys, sells, and names. Edit anything. A company name only resolves to a ticker when a line here says so, for example “%@ means %@”.",
                    "英伟达", "NVDA"
                )
            )
        }
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
                failure =
                    (error as? LocalizedError)?.errorDescription
                    ?? L10n.string("CopyTrading could not learn from this channel.")
            }
        }
    }
}
