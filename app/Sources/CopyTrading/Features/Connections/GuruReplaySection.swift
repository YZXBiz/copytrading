import DesktopCore
import SwiftUI

/// Before a guru is switched on (ADR-0007): their recent posts read with this draft's playbook and
/// rules, each saying what it would have done. Nothing is placed or saved.
struct GuruReplaySection: View {
    let route: TradingRouteDraft
    /// Each account's limits, by name: a replayed buy shows what the maximum per order lets through.
    let policies: [String: TradingAccountPolicy]
    let replay: (TradingRouteDraft) async throws -> GuruReplay
    @State private var result: GuruReplay?
    @State private var failure: String?
    @State private var isReplaying = false

    var body: some View {
        SheetSection(
            L10n.string("Try it on recent posts"), detail: L10n.string("See what their last posts would have done with these settings.")
        ) {
            Button(
                L10n.string(result == nil ? "Replay Recent Posts" : "Replay Again"), systemImage: "arrow.clockwise",
                action: run
            )
            .buttonStyle(SheetQuietButtonStyle())
            .padding(.vertical, 12)
            .disabled(isReplaying)
            .accessibilityIdentifier("guru.replay")
            if isReplaying {
                ProgressView(L10n.string("Reading recent posts…")).controlSize(.small)
            }
            if let failure {
                Text(failure).foregroundStyle(StatusTone.caution.color)
            }
            if let result {
                Text(tally(result.posts))
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                    .padding(.bottom, 4)
                ForEach(Array(result.posts.enumerated()), id: \.offset) { _, post in
                    row(post)
                }
            }
        } footer: {
            Text(L10n.string("Reads their last 15 posts with your model, which may cost a little. Nothing is bought or sold."))
        }
    }

    private func row(_ post: ReplayedPost) -> some View {
        let outcome = Outcome(post, policies: policies)
        return VStack(alignment: .leading, spacing: 4) {
            Text(post.text)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(outcome.word, systemImage: outcome.tone.symbol)
                    .foregroundStyle(outcome.tone.color)
                    .fixedSize()
                if let detail = outcome.detail {
                    Text(detail)
                        .foregroundStyle(Palette.secondaryInk)
                        .monospacedDigit()
                }
            }
            .font(DesignTokens.caption)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What a replayed post would have done, in the Activity card's words.
    @MainActor
    struct Outcome {
        enum Kind { case trade, wait, ignored, unreadable }

        let kind: Kind
        let detail: String?

        init(_ post: ReplayedPost, policies: [String: TradingAccountPolicy] = [:]) {
            switch post.decision {
            case "trade":
                let lines = (post.reading.map { $0.calls.map(ReadAsText.line) } ?? []) + Self.amounts(post, policies: policies)
                (kind, detail) = (.trade, lines.isEmpty ? nil : L10n.sentences(lines))
            case "ignore":
                (kind, detail) = (.ignored, nil)
            default:
                let waits = post.reading != nil || !post.suggested.isEmpty
                (kind, detail) = (waits ? .wait : .unreadable, Reason.text(post.reason))
            }
        }

        /// What each account would spend on the post's buys: the guru's share of its full position,
        /// trimmed by the account's maximum per order, as the engine trims it.
        static func amounts(_ post: ReplayedPost, policies: [String: TradingAccountPolicy]) -> [String] {
            post.destinations.compactMap { destination in
                guard destination.action == .buy, let budget = destination.budgetUSD.flatMap({ Decimal(string: $0) }) else {
                    return nil
                }
                let maximum = policies[destination.accountID].flatMap { Decimal(string: $0.maxOrderUSD.trimmed) }
                let spend = maximum.map { min(budget, $0) } ?? budget
                return L10n.sentence(L10n.string("%@ into %@", Humanize.dollars("\(spend)"), destination.accountID))
            }
        }

        var word: String {
            switch kind {
            case .trade: L10n.string("Would trade")
            case .wait: L10n.string("Would wait for you")
            case .ignored: L10n.string("Ignored")
            case .unreadable: L10n.string("Couldn't read")
            }
        }

        var tone: StatusTone {
            switch kind {
            case .trade: .positive
            case .wait: .caution
            case .ignored: .inactive
            case .unreadable: .critical
            }
        }
    }

    private func tally(_ posts: [ReplayedPost]) -> String {
        let kinds = posts.map { Outcome($0).kind }
        let trades = kinds.filter { $0 == .trade }.count
        let waits = kinds.filter { $0 == .wait }.count
        return L10n.string(
            "%lld posts: %lld would trade, %lld would wait for you, %lld would not.", Int64(posts.count), Int64(trades),
            Int64(waits), Int64(posts.count - trades - waits))
    }

    private func run() {
        isReplaying = true
        failure = nil
        Task {
            defer { isReplaying = false }
            do {
                result = try await replay(route)
            } catch {
                failure =
                    (error as? LocalizedError)?.errorDescription ?? L10n.string("The engine could not replay this channel. Try again.")
            }
        }
    }
}
