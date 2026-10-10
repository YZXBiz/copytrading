import DesktopCore
import SwiftUI

/// The Activity card (ADR-0007): the post with the words the reader cited, how it was read, and
/// what each account did, on one reading surface; technical evidence follows on the canvas.
struct ActivityDetailView: View {
    let item: SourceActivity
    let guruName: String?
    let canReview: Bool
    let canEvaluate: Bool
    let skippedCalls: SkippedCalls
    let review: () -> Void
    /// Copies the calls a post waits on, through the review sheet's preview and confirmation.
    let copy: (WaitingCall) -> Void
    let evaluate: () -> Void
    /// Opens an account's limits on Maximum above signal price; the card never changes it itself.
    var editLimits: (String) -> Void = { _ in }
    /// Opens Accounts at an account whose holdings hold this call back.
    var reviewHoldings: (String) -> Void = { _ in }
    /// Accounts that hold this post's buy until the owner resumes their entries after a restart.
    var resume: ResumeWait = .none
    /// Resumes an account's entries, as Accounts' button does.
    var resumeEntries: (String) -> Void = { _ in }
    /// The one account Activity is showing, or every account.
    var accountID: String?
    @State private var readerPosition = ScrollPosition(edge: .top)
    /// The post this card watched in flight, so its fill can end the live moment with a hop.
    @State private var watchedInFlight: String?
    @Environment(\.postProgressContext) private var progressContext

    private var outcome: ActivityCardOutcome {
        ActivityCardOutcome(item, skipped: skippedCalls.contains(item.sourceID), resume: resume)
    }

    private var progress: PostProgress? {
        PostProgress(item, context: progressContext, resume: resume)
    }

    private var isBeingRead: Bool {
        item.decision == nil && progress != nil
    }

    private var hasFilled: Bool {
        item.destinations.flatMap(\.orders).contains { ["filled", "partially_filled"].contains($0.status) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                card
                // The trip at a glance; a post still in flight shows its live moment instead.
                if progress == nil, PostTimeline(item).phases.count >= 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        ActivityLabel(text: L10n.string("Timeline"))
                        PostJourneyLine(timeline: PostTimeline(item))
                    }
                }
                ActivityTechnicalDetails(item: item)
                    .id(item.sourceID)
            }
            .frame(maxWidth: DesignTokens.readingContentMaxWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollPosition($readerPosition)
        .defaultScrollAnchor(.top, for: .initialOffset)
        .onChange(of: item.sourceID) { _, _ in
            readerPosition.scrollTo(edge: .top)
        }
        .onChange(of: progress == nil, initial: true) { _, settled in
            if !settled { watchedInFlight = item.sourceID }
        }
    }

    /// The post on the page itself: who and when, their words large, how they were read, then what
    /// each account did, parted by whitespace and hairlines, never a frame.
    private var card: some View {
        let outcome = outcome
        return VStack(alignment: .leading, spacing: 0) {
            header(outcome)
            quote.padding(.top, 18)
            liveMoment.padding(.top, 28)
            // A post still being read has no reading or accounts yet; the moment above says so.
            // What the post asked for comes first, compact; then what each account did with it.
            if !isBeingRead {
                readAs.padding(.top, 30)
                if item.decision != "ignore" {
                    accounts(outcome).padding(.top, 34)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// While the post is read or its order goes out, and once more when that order fills.
    @ViewBuilder
    private var liveMoment: some View {
        if let progress {
            PostLiveMoment(progress: progress, filledLine: "")
        } else if watchedInFlight == item.sourceID, hasFilled {
            PostLiveMoment(progress: nil, filledLine: filledLine)
        }
    }

    private var filledLine: String {
        outcome.accounts.lazy.flatMap(\.results).first?.headline ?? ""
    }

    /// The guru's own words as a large quoted line in the display face, so they never read as the
    /// app's.
    private var quote: some View {
        ActivitySourceContentView(item: item, citedWords: item.reading?.citedWords ?? [])
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Zhao · Oct 8 at 12:38 PM", quiet above the quote, with the post's state in tracked
    /// capitals: amber only while it waits on the owner.
    private func header(_ outcome: ActivityCardOutcome) -> some View {
        let waits = outcome.accounts.contains { $0.waits || $0.awaitsResume }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                author
                Spacer(minLength: 8)
                ActivityLabel(text: outcome.title, color: waits ? Palette.amber : Palette.tertiaryInk)
            }
            VStack(alignment: .leading, spacing: 8) {
                author
                ActivityLabel(text: outcome.title, color: waits ? Palette.amber : Palette.tertiaryInk)
            }
        }
    }

    private var author: some View {
        HStack(spacing: 8) {
            GuruMonogram(name: guruName ?? "?", size: 20)
            Text(
                L10n.string(
                    "%@ · %@", guruName ?? L10n.string("Unknown guru"), Humanize.postTime(item.sourceAt))
            )
            .font(DesignTokens.lede)
            .tracking(DesignTokens.ledeTracking)
            .foregroundStyle(Palette.tertiaryInk)
            .monospacedDigit()
            .lineLimit(1)
        }
    }

    /// How the reader read the post under a tracked-capital label: one plain line per call, what
    /// the call leaves out, then what kind of post it was and who read it.
    private var readAs: some View {
        VStack(alignment: .leading, spacing: 4) {
            ActivityLabel(text: L10n.string("Read as"))
                .padding(.bottom, 4)
            if let reading = item.reading {
                if reading.calls.isEmpty {
                    readLine(ReadAsText.lines(reading).first ?? "")
                    subline([ReadAsText.kind(reading), readBy].compactMap(\.self))
                } else {
                    ForEach(Array(reading.calls.enumerated()), id: \.offset) { index, call in
                        let headline = ReadAsText.headline(call)
                        VStack(alignment: .leading, spacing: 2) {
                            readLine(headline.title)
                            detailLine(
                                [
                                    headline.detail, ReadAsText.note(call),
                                    ReadAsText.isRepost(call) ? L10n.string("a re-post of an earlier call") : nil,
                                ]
                                .compactMap(\.self))
                        }
                        .padding(.top, index == 0 ? 0 : 8)
                    }
                    subline([ReadAsText.kind(reading), readBy].compactMap(\.self)).padding(.top, 4)
                }
            } else {
                readLine(item.headline)
                if let reason = Reason.parserMessage(item.parserReason, needsReview: item.needsManualReview) {
                    detailLine([reason])
                }
            }
            if WaitingCall(item) == nil, item.needsManualReview || item.isHistorical {
                actions.padding(.top, 10)
            }
        }
    }

    private func readLine(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.bodyEmphasis)
            .foregroundStyle(Palette.ink)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What the call leaves out or adds, in one line under its headline: "No size given · full position".
    @ViewBuilder
    private func detailLine(_ parts: [String]) -> some View {
        if !parts.isEmpty {
            Text(capitalized(parts.joined(separator: " · ")))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Who read the post, under the first call.
    private var readBy: String? {
        item.interpretedBy.map { L10n.string("read by %@", $0) }
    }

    /// The reading's quiet facts on one line: what kind of post it was, what the sentence leaves out.
    private func subline(_ parts: [String]) -> some View {
        Text(capitalized(parts.joined(separator: " · ")))
            .font(DesignTokens.activityMeta)
            .foregroundStyle(Palette.tertiaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func capitalized(_ line: String) -> String {
        line.prefix(1).uppercased() + line.dropFirst()
    }

    /// What each account did with the post, takeaway first, with Copy and Skip where one waits.
    /// Each account is its own block under its name and Paper/Live in tracked capitals, parted from
    /// the next by whitespace alone, so the page keeps its few lines for what they draw.
    @ViewBuilder
    private func accounts(_ outcome: ActivityCardOutcome) -> some View {
        let shown = outcome.accounts.filter { accountID == nil || $0.id == accountID }
        VStack(alignment: .leading, spacing: 36) {
            if shown.isEmpty {
                // "Yet" only while the trade is still on its way to the accounts; once delivered with
                // no account attached, none will act on it.
                let onTheWay = item.decision == "trade" && item.deliveryStatus != "delivered"
                Text(
                    onTheWay
                        ? L10n.string("No account has acted on this post yet.")
                        : L10n.string("No account was asked to act on this post.")
                )
                .font(DesignTokens.activityBody)
                .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(shown) { account in
                accountRow(account)
            }
        }
    }

    /// One account's result: whose it is, then for each order the outcome as one big sentence with
    /// its mark, the price ruler, the numbers behind it, and at most one thing to do.
    private func accountRow(_ account: ActivityCardOutcome.Account) -> some View {
        let environment = TradingEnvironment(rawValue: account.environment) ?? .paper
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                ActivityLabel(text: account.id)
                ActivityLabel(text: " · ")
                ActivityLabel(
                    text: L10n.string(environment == .live ? "Live" : "Paper"),
                    color: environment == .live ? .orange : Palette.tertiaryInk)
            }
            ForEach(Array(account.results.enumerated()), id: \.offset) { index, result in
                resultBlock(result, tone: tone(of: index, in: account), account: account.id)
                    .padding(.top, index == 0 ? 0 : 14)
            }
            if account.waits, let waiting = WaitingCall(item) {
                waitingActions(waiting)
            }
            if account.awaitsResume {
                Button(L10n.string("Resume Entries")) { resumeEntries(account.id) }
                    .buttonStyle(PageButtonStyle(isProminent: true))
                    .accessibilityIdentifier("activity.resumeEntries")
                    .accessibilityHint(L10n.string("Allows new entries in this account, so the held buy can be copied."))
            }
            if heldByHoldings(account.id) {
                Button(L10n.string("Review in Accounts")) { reviewHoldings(account.id) }
                    .buttonStyle(QuietTextButtonStyle())
                    .accessibilityIdentifier("activity.reviewHoldings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Account %@", account.id))
    }

    /// How one result ended, for its mark: an order's own outcome; otherwise waiting on the owner,
    /// or a call the account did not carry out.
    private func tone(of index: Int, in account: ActivityCardOutcome.Account) -> StatusTone {
        let orders = item.destinations.first { $0.accountID == account.id }?.orders ?? []
        if orders.indices.contains(index) {
            return DestinationOutcome.order(orders[index], count: 1).tone
        }
        return account.waits || account.awaitsResume ? .caution : .inactive
    }

    private func resultBlock(_ result: ActivityCardOutcome.Result, tone: StatusTone, account: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                OutcomeMark(tone: tone)
                    .padding(.top, 4)
                Text(result.headline)
                    .font(DisplayFont.font(size: 22, weight: .medium, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let prices = result.prices {
                PriceRuler(points: prices)
            }
            if !result.facts.isEmpty {
                ActivityFactPairs(facts: result.facts)
            }
            if let note = result.note {
                Text(note)
                    .font(DesignTokens.activityBody)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result.suggestion == .allowAboveGuru {
                Button(L10n.string("Allow 1% above the guru's price")) { editLimits(account) }
                    .buttonStyle(QuietTextButtonStyle())
                    .accessibilityIdentifier("activity.allowAboveGuru")
                    .accessibilityHint(
                        L10n.string("Opens this account's limits at Maximum above signal price. Nothing changes until you save."))
            }
        }
    }

    /// The account refused this call until its holdings are settled, which happens in Accounts.
    private func heldByHoldings(_ accountID: String) -> Bool {
        item.destinations.contains { $0.accountID == accountID && $0.instructionOutcomes.contains("ownership_incident") }
    }

    @ViewBuilder
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(alignment: .leading, spacing: 8) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if item.needsManualReview {
            Button(L10n.string("Review and Correct…"), action: review)
                .buttonStyle(PageButtonStyle(isProminent: true))
                .disabled(!canReview)
                .accessibilityHint(L10n.string("Opens the reviewed correction, preview, and confirmation workflow."))
        }
        evaluateButton
    }

    /// A call that waits for the owner (ADR-0007): copy it, or skip it, until its trading day ends.
    private func waitingActions(_ waiting: WaitingCall) -> some View {
        HStack(spacing: 8) {
            Button(
                L10n.string(waiting.calls.isEmpty ? "Enter Trade…" : waiting.awaitsApproval ? "Approve…" : "Copy…"),
                action: { copy(waiting) }
            )
            .buttonStyle(PageButtonStyle(isProminent: true))
            .disabled(!canReview)
            .accessibilityIdentifier("activity.copy")
            .accessibilityHint(L10n.string("Opens the call to check, then previews the order in each waiting account."))
            Button(L10n.string("Skip")) { skippedCalls.skip(item.sourceID) }
                .buttonStyle(QuietTextButtonStyle())
                .accessibilityIdentifier("activity.skip")
        }
    }

    @ViewBuilder
    private var evaluateButton: some View {
        if item.isHistorical {
            Button(L10n.string("Evaluate with Saved Profile…"), action: evaluate)
                .buttonStyle(QuietTextButtonStyle())
                .disabled(!canEvaluate)
                .accessibilityIdentifier("activity.evaluateHistorical")
                .accessibilityHint(L10n.string("Runs a simulated interpretation and destination sizing preview with no order submission."))
        }
    }
}
