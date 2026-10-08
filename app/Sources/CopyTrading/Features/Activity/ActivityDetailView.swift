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
    @Environment(\.postProgressContext) private var progressContext

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
            VStack(alignment: .leading, spacing: 0) {
                header(outcome)
                if let progress = PostProgress(item, context: progressContext, resume: resume) {
                    PostProgressLabel(progress: progress)
                        .font(DesignTokens.activityMeta.weight(.medium))
                        .padding(.top, 12)
                }
                quote.padding(.top, 16)
                readAs.padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
            if item.decision != "ignore" {
                hairline
                accounts(outcome)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.readingCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.readingCornerRadius)
                .strokeBorder(Palette.hairline.opacity(0.7), lineWidth: 1)
        }
    }

    /// The guru's own words on a quiet tinted block, so they never read as the app's.
    private var quote: some View {
        ActivitySourceContentView(item: item, citedWords: item.reading?.citedWords ?? [])
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.group, in: .rect(cornerRadius: DesignTokens.calloutCornerRadius))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hairline: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }

    private func header(_ outcome: ActivityCardOutcome) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                author
                Spacer(minLength: 8)
                StatusDotLabel(text: outcome.title, tone: outcome.tone)
            }
            VStack(alignment: .leading, spacing: 8) {
                author
                StatusDotLabel(text: outcome.title, tone: outcome.tone)
                    .padding(.leading, 30)
            }
        }
    }

    private var author: some View {
        HStack(spacing: 8) {
            GuruMonogram(name: guruName ?? "?", size: 22)
            Text(guruName ?? L10n.string("Unknown guru"))
                .font(DesignTokens.activityBody.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(Humanize.postTime(item.sourceAt))
                .font(DesignTokens.activityBody)
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.activityMeta)
            .foregroundStyle(Palette.secondaryInk)
    }

    /// How the reader read the post: one headline per call, what the call leaves out, then what
    /// kind of post it was and who read it.
    private var readAs: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reading = item.reading {
                if reading.calls.isEmpty {
                    readLine(ReadAsText.lines(reading).first ?? "")
                    subline([ReadAsText.kind(reading), readBy].compactMap(\.self))
                } else {
                    ForEach(Array(reading.calls.enumerated()), id: \.offset) { index, call in
                        let headline = ReadAsText.headline(call)
                        VStack(alignment: .leading, spacing: 4) {
                            readLine(headline.title)
                            detailLine(
                                [
                                    headline.detail, ReadAsText.note(call),
                                    ReadAsText.isRepost(call) ? L10n.string("a re-post of an earlier call") : nil,
                                ]
                                .compactMap(\.self))
                        }
                        .padding(.top, index == 0 ? 0 : 12)
                    }
                    subline([ReadAsText.kind(reading), readBy].compactMap(\.self)).padding(.top, 4)
                }
            } else {
                label(L10n.string("Read as"))
                Text(item.headline)
                    .font(DesignTokens.activityBody)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = Reason.parserMessage(item.parserReason, needsReview: item.needsManualReview) {
                    Text(reason)
                        .font(DesignTokens.activityBody)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if WaitingCall(item) == nil, item.needsManualReview || item.isHistorical {
                actions.padding(.top, 8)
            }
        }
    }

    private func readLine(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.activityHeadline)
            .foregroundStyle(Palette.ink)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What the call leaves out or adds, in one line under its headline: "No size given · full position".
    @ViewBuilder
    private func detailLine(_ parts: [String]) -> some View {
        if !parts.isEmpty {
            Text(capitalized(parts.joined(separator: " · ")))
                .font(DesignTokens.activityBody)
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
    /// Each account is its own block, led by its name and Paper/Live, so whose result it is is
    /// never unclear.
    @ViewBuilder
    private func accounts(_ outcome: ActivityCardOutcome) -> some View {
        let shown = outcome.accounts.filter { accountID == nil || $0.id == accountID }
        VStack(alignment: .leading, spacing: 0) {
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
                .padding(24)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Rectangle().fill(Palette.hairline.opacity(0.6)).frame(height: 1).padding(.horizontal, 24)
                }
                accountRow(account, showsStatus: shown.count > 1)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
        }
    }

    /// One account's result: whose it is, then for each order the takeaway in one bold line, the
    /// numbers behind it, and at most one thing to do.
    private func accountRow(_ account: ActivityCardOutcome.Account, showsStatus: Bool) -> some View {
        let environment = TradingEnvironment(rawValue: account.environment) ?? .paper
        let status = item.destinations.first { $0.accountID == account.id }.map(DestinationOutcome.init)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(account.id)
                    .foregroundStyle(Palette.secondaryInk)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(L10n.string(environment == .live ? "Live" : "Paper"))
                    .foregroundStyle(environment == .live ? Color.orange : Palette.tertiaryInk)
                Spacer(minLength: 16)
                if showsStatus, let status {
                    StatusDotLabel(text: status.title, tone: status.tone, font: DesignTokens.activityMeta.weight(.medium))
                }
            }
            .font(DesignTokens.activityMeta)
            ForEach(Array(account.results.enumerated()), id: \.offset) { _, result in
                resultBlock(result, account: account.id)
            }
            if account.waits, let waiting = WaitingCall(item) {
                waitingActions(waiting)
            }
            if account.awaitsResume {
                Button(L10n.string("Resume Entries"), systemImage: "play.fill") { resumeEntries(account.id) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.green)
                    .accessibilityIdentifier("activity.resumeEntries")
                    .accessibilityHint(L10n.string("Allows new entries in this account, so the held buy can be copied."))
            }
            if heldByHoldings(account.id) {
                Button(L10n.string("Review in Accounts")) { reviewHoldings(account.id) }
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("activity.reviewHoldings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Account %@", account.id))
    }

    private func resultBlock(_ result: ActivityCardOutcome.Result, account: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.headline)
                .font(DesignTokens.activityOutcome)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if !result.facts.isEmpty {
                ActivityFactChips(facts: result.facts)
            }
            if let note = result.note {
                Text(note)
                    .font(DesignTokens.activityBody)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result.suggestion == .allowAboveGuru {
                Button(L10n.string("Allow 1% above the guru's price"), systemImage: "slider.horizontal.3") { editLimits(account) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Palette.accent)
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
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, 6)
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
