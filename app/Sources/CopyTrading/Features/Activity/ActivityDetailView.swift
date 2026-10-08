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
    /// Opens Accounts at an account whose holdings hold this call back.
    var reviewHoldings: (String) -> Void = { _ in }
    /// Accounts that hold this post's buy until the owner resumes their entries after a restart.
    var resume: ResumeWait = .none
    /// Resumes an account's entries, as Accounts' button does.
    var resumeEntries: (String) -> Void = { _ in }
    @State private var readerPosition = ScrollPosition(edge: .top)

    private var outcome: ActivityCardOutcome {
        ActivityCardOutcome(item, skipped: skippedCalls.contains(item.sourceID), resume: resume)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                card
                ActivityTechnicalDetails(item: item)
                    .id(item.sourceID)
                    .padding(.horizontal, 22)
            }
            .frame(maxWidth: DesignTokens.readingContentMaxWidth, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollPosition($readerPosition)
        .defaultScrollAnchor(.top, for: .initialOffset)
        .onChange(of: item.sourceID) { _, _ in
            readerPosition.scrollTo(edge: .top)
        }
    }

    private var card: some View {
        let outcome = outcome
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header(outcome)
                ActivitySourceContentView(item: item, citedWords: item.reading?.citedWords ?? [])
            }
            .padding(22)
            hairline
            readAs.padding(22)
            if item.decision != "ignore" {
                hairline
                accounts(outcome).padding(22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.readingCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.readingCornerRadius)
                .strokeBorder(Palette.hairline.opacity(0.7), lineWidth: 1)
        }
    }

    private var hairline: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }

    private func header(_ outcome: ActivityCardOutcome) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                author
                Spacer(minLength: 8)
                StatusBadge(outcome.title, tone: outcome.tone)
            }
            VStack(alignment: .leading, spacing: 8) {
                author
                StatusBadge(outcome.title, tone: outcome.tone)
                    .padding(.leading, 42)
            }
        }
    }

    private var author: some View {
        HStack(spacing: 10) {
            GuruMonogram(name: guruName ?? "?", size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(guruName ?? L10n.string("Unknown guru"))
                    .font(DesignTokens.personTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(Humanize.postTime(item.sourceAt))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(2)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.caption.weight(.medium))
            .foregroundStyle(Palette.tertiaryInk)
    }

    /// How the reader read the post: its kind, one line per call, and the facts behind them.
    private var readAs: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reading = item.reading {
                label(L10n.string("Read as · %@", ReadAsText.kind(reading)))
                if reading.calls.isEmpty {
                    readLine(ReadAsText.lines(reading).first ?? "")
                } else {
                    ForEach(Array(reading.calls.enumerated()), id: \.offset) { index, call in
                        VStack(alignment: .leading, spacing: 8) {
                            readLine(ReadAsText.line(call))
                            facts(ReadAsText.facts(call))
                        }
                        .padding(.top, index == 0 ? 0 : 6)
                    }
                }
            } else {
                label(L10n.string("Read as"))
                Text(item.headline)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = Reason.parserMessage(item.parserReason, needsReview: item.needsManualReview) {
                    Text(reason)
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if WaitingCall(item) == nil, item.needsManualReview || item.isHistorical {
                actions.padding(.top, 4)
            }
        }
    }

    private func readLine(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.cardSerif)
            .foregroundStyle(Palette.ink)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func facts(_ facts: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(facts, id: \.self) { fact in
                Text(fact)
                    .font(DesignTokens.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.well, in: .rect(cornerRadius: 6))
            }
        }
    }

    /// What each account did with the post, and why, with Copy and Skip where one waits.
    @ViewBuilder
    private func accounts(_ outcome: ActivityCardOutcome) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if outcome.accounts.isEmpty {
                // "Yet" only while the trade is still on its way to the accounts; once delivered with
                // no account attached, none will act on it.
                let onTheWay = item.decision == "trade" && item.deliveryStatus != "delivered"
                label(L10n.string("Your account"))
                Text(
                    onTheWay
                        ? L10n.string("No account has acted on this post yet.")
                        : L10n.string("No account was asked to act on this post.")
                )
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(outcome.accounts) { account in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        label(L10n.string("Your account · %@", account.id))
                        if let environment = TradingEnvironment(rawValue: account.environment), environment == .live {
                            EnvironmentBadge(environment: environment)
                        }
                    }
                    ForEach(Array(account.lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.what)
                                .font(DesignTokens.bodyEmphasis.scaled(by: 15.0 / 14))
                                .foregroundStyle(Palette.ink)
                                .monospacedDigit()
                            if let why = line.why {
                                Text(why)
                                    .font(DesignTokens.bodyText)
                                    .foregroundStyle(Palette.secondaryInk)
                                    .monospacedDigit()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if account.waits, let waiting = WaitingCall(item) {
                        waitingActions(waiting).padding(.top, 6)
                    }
                    if account.awaitsResume {
                        Button(L10n.string("Resume Entries"), systemImage: "play.fill") { resumeEntries(account.id) }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(.green)
                            .padding(.top, 6)
                            .accessibilityIdentifier("activity.resumeEntries")
                            .accessibilityHint(L10n.string("Allows new entries in this account, so the held buy can be copied."))
                    }
                    if heldByHoldings(account.id) {
                        Button(L10n.string("Review in Accounts")) { reviewHoldings(account.id) }
                            .controlSize(.small)
                            .padding(.top, 4)
                            .accessibilityIdentifier("activity.reviewHoldings")
                    }
                }
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
            Button(L10n.string("Review and Correct…"), systemImage: "pencil.and.list.clipboard", action: review)
                .buttonStyle(.borderedProminent)
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
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!canReview)
            .accessibilityIdentifier("activity.copy")
            .accessibilityHint(L10n.string("Opens the call to check, then previews the order in each waiting account."))
            Button(L10n.string("Skip")) { skippedCalls.skip(item.sourceID) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("activity.skip")
        }
    }

    @ViewBuilder
    private var evaluateButton: some View {
        if item.isHistorical {
            Button(L10n.string("Evaluate with Saved Profile…"), systemImage: "wand.and.stars", action: evaluate)
                .disabled(!canEvaluate)
                .accessibilityIdentifier("activity.evaluateHistorical")
                .accessibilityHint(L10n.string("Runs a simulated interpretation and destination sizing preview with no order submission."))
        }
    }
}
