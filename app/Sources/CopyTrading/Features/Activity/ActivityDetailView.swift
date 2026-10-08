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
    /// The one account Activity is showing, or every account.
    var accountID: String?
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
            VStack(alignment: .leading, spacing: 0) {
                header(outcome)
                quote.padding(.top, 20)
                readAs.padding(.top, 22)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 22)
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

    /// The guru's own words, set off like a quotation so they never read as the app's.
    private var quote: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 1.25)
                .fill(Palette.accent.opacity(0.55))
                .frame(width: 2.5)
            ActivitySourceContentView(item: item, citedWords: item.reading?.citedWords ?? [])
        }
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
                    .padding(.leading, 36)
            }
        }
    }

    private var author: some View {
        HStack(spacing: 10) {
            GuruMonogram(name: guruName ?? "?", size: 26)
            Text(guruName ?? L10n.string("Unknown guru"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(Humanize.postTime(item.sourceAt))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .monospacedDigit()
                .lineLimit(1)
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
                if reading.calls.isEmpty {
                    readLine(ReadAsText.lines(reading).first ?? "")
                    subline([ReadAsText.kind(reading), readBy].compactMap(\.self))
                } else {
                    ForEach(Array(reading.calls.enumerated()), id: \.offset) { index, call in
                        let headline = ReadAsText.headline(call)
                        VStack(alignment: .leading, spacing: 3) {
                            readLine(headline.title)
                            if let detail = headline.detail {
                                Text(detail)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Palette.secondaryInk)
                                    .monospacedDigit()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            subline(
                                [
                                    index == 0 ? ReadAsText.kind(reading) : nil, ReadAsText.note(call),
                                    ReadAsText.isRepost(call) ? L10n.string("a re-post of an earlier call") : nil,
                                    index == 0 ? readBy : nil,
                                ]
                                .compactMap(\.self)
                            )
                            .padding(.top, 5)
                        }
                        .padding(.top, index == 0 ? 0 : 14)
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
            .font(.system(size: 21, weight: .semibold))
            .tracking(-0.3)
            .foregroundStyle(Palette.ink)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Who read the post, under the first call.
    private var readBy: String? {
        item.interpretedBy.map { L10n.string("read by %@", $0) }
    }

    /// The reading's quiet facts on one line: what kind of post it was, what the sentence leaves out.
    private func subline(_ parts: [String]) -> some View {
        let line = parts.joined(separator: " · ")
        return Text(line.prefix(1).uppercased() + line.dropFirst())
            .font(DesignTokens.caption)
            .foregroundStyle(Palette.tertiaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What each account did with the post, and why, with Copy and Skip where one waits. Each
    /// account is its own row, led by its name and Paper/Live badge, so it is never unclear whose
    /// result this is.
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
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .padding(22)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Rectangle().fill(Palette.hairline.opacity(0.6)).frame(height: 1).padding(.leading, 140)
                }
                accountRow(account, showsStatus: shown.count > 1)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
            }
        }
    }

    /// One account's result as a ledger row: whose it is on the left, what happened in the middle,
    /// and its own status on the right when the card covers several accounts.
    private func accountRow(_ account: ActivityCardOutcome.Account, showsStatus: Bool) -> some View {
        let environment = TradingEnvironment(rawValue: account.environment) ?? .paper
        let status = item.destinations.first { $0.accountID == account.id }.map(DestinationOutcome.init)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.id)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(L10n.string(environment == .live ? "Live" : "Paper"))
                    .font(DesignTokens.caption.weight(.medium))
                    .foregroundStyle(environment == .live ? Color.orange : Palette.tertiaryInk)
            }
            .frame(width: 112, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(account.lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.what)
                            .font(DesignTokens.bodyText)
                            .foregroundStyle(Palette.ink)
                            .monospacedDigit()
                        if let why = line.why {
                            Text(why)
                                .font(DesignTokens.caption)
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
            Spacer(minLength: 16)
            if showsStatus, let status {
                StatusDotLabel(text: status.title, tone: status.tone)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Account %@", account.id))
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
