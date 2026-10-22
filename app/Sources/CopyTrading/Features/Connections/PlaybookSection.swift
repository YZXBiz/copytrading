import DesktopCore
import SwiftUI

/// How the model should read this guru: learned from the channel, then edited by the owner.
struct PlaybookSection: View {
    @Binding var route: TradingRouteDraft
    let learn: (TradingRouteDraft) async throws -> LearnedGuruPlaybook
    @State private var isLearning = false
    @State private var learned: LearnedGuruPlaybook?
    @State private var failure: String?
    @FocusState private var isEditing: Bool

    var body: some View {
        SheetSection(L10n.string("Playbook")) {
            VStack(alignment: .leading, spacing: 8) {
                if let learned {
                    Callout(learnedSummary(learned), tone: .positive)
                        .accessibilityIdentifier("playbook.summary")
                }
                if let failure {
                    Callout(failure, tone: .critical)
                        .accessibilityIdentifier("playbook.failure")
                }
                // In the same well as every field in the sheet, tall enough to read several lines.
                TextEditor(text: $route.playbook)
                    .font(DesignTokens.bodyText)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .focused($isEditing)
                    .padding(8)
                    .background(Palette.well, in: .rect(cornerRadius: DesignTokens.sheetControlRadius))
                    .accessibilityLabel(L10n.string("Playbook"))
                    .accessibilityIdentifier("playbook.text")
            }
        } accessory: {
            HStack(spacing: 8) {
                if isLearning {
                    ProgressView()
                        .controlSize(.small)
                        .help(L10n.string("Reading recent posts…"))
                }
                Button(action: start) {
                    Label(
                        L10n.string(route.playbook.trimmedLines.isEmpty ? "Learn from Channel" : "Learn Again"),
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(SheetQuietButtonStyle())
                .disabled(isLearning)
                .accessibilityIdentifier("playbook.learn")
            }
        } footer: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L10n.string("One rule per line, such as “%@ means %@”.", "英伟达", "NVDA"))
                Spacer(minLength: 12)
                Text(
                    L10n.string("%@ of %@ characters", route.playbook.count.formatted(), tradingPlaybookMaxLength.formatted())
                )
                .foregroundStyle(route.playbook.count > tradingPlaybookMaxLength ? Palette.loss : Palette.tertiaryInk)
                .monospacedDigit()
            }
        }
    }

    /// What Learn did, truthfully: the playbook is drafted.
    @MainActor
    private func learnedSummary(_ learned: LearnedGuruPlaybook) -> String {
        let sentences = [
            L10n.string("Read %lld posts with %@.", Int64(learned.postsRead), learned.model),
            learned.summary,
            L10n.string("The playbook is drafted; read it over before you start copying."),
        ]
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
                learned = result
            } catch {
                learned = nil
                failure = AppModel.userMessage(for: error)
            }
        }
    }
}
