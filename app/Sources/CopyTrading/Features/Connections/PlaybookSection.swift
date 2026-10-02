import DesktopCore
import SwiftUI

/// How the model should read this guru: learned from the channel, then edited by the owner.
struct PlaybookSection: View {
    @Binding var route: TradingRouteDraft
    let learn: (TradingRouteDraft) async throws -> LearnedGuruPlaybook
    @State private var isLearning = false
    @State private var learned: LearnedGuruPlaybook?
    @State private var failure: String?

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button(action: start) {
                    Label(
                        L10n.string(route.playbook.trimmedLines.isEmpty ? "Learn from Channel" : "Learn Again"),
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLearning)
                .accessibilityIdentifier("playbook.learn")
                if isLearning {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("Reading recent posts…"))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let learned {
                Callout(learnedSummary(learned), tone: .positive)
                    .accessibilityIdentifier("playbook.summary")
            }
            if let failure {
                Callout(failure, tone: .critical)
                    .accessibilityIdentifier("playbook.failure")
            }
            TextEditor(text: $route.playbook)
                .font(.body)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Palette.group, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
                .accessibilityLabel(L10n.string("Playbook"))
                .accessibilityIdentifier("playbook.text")
            Text(L10n.string("%@ of %@ characters", route.playbook.count.formatted(), tradingPlaybookMaxLength.formatted()))
                .font(.caption)
                .foregroundStyle(route.playbook.count > tradingPlaybookMaxLength ? .red : .secondary)
                .monospacedDigit()
        } header: {
            Text(L10n.string("Playbook"))
        } footer: {
            Text(
                L10n.string(
                    "Learn reads the channel's recent posts and drafts how this guru writes buys, sells, and names. Edit anything. A company name only resolves to a ticker when a line here says so, for example “%@ means %@”.",
                    "英伟达", "NVDA"
                )
            )
        }
    }

    @MainActor
    private func learnedSummary(_ learned: LearnedGuruPlaybook) -> String {
        let examples =
            learned.examples.count == 1
            ? L10n.string("1 example")
            : L10n.string("%lld examples", Int64(learned.examples.count))
        return L10n.string(
            "Read %lld posts with %@. %@ Filled in the playbook, prefix, exit basis, and %@; review them before validating.",
            Int64(learned.postsRead), learned.model, learned.summary, examples
        )
    }

    private func start() {
        isLearning = true
        failure = nil
        Task {
            defer { isLearning = false }
            do {
                let result = try await learn(route)
                route.playbook = result.playbook
                if let prefix = result.prefix { route.prefix = prefix }
                route.exitBasis = result.exitBasis
                route.examples = result.examples.map(TradingProfileExampleDraft.init(example:))
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
