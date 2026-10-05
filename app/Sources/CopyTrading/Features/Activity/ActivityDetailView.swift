import DesktopCore
import SwiftUI

/// The original post is a reading surface; interpretation and account evidence follow on the canvas.
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
    @State private var readerPosition = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sourcePage
                VStack(alignment: .leading, spacing: 20) {
                    understood
                    Divider()
                    results
                    ActivityTechnicalDetails(item: item)
                        .id(item.sourceID)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
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

    private var sourcePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            ActivitySourceContentView(item: item)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.readingCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.readingCornerRadius)
                .strokeBorder(Palette.hairline.opacity(0.7), lineWidth: 1)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                author
                Spacer(minLength: 8)
                StatusBadge(decisionLabel, tone: item.decisionTone)
            }
            VStack(alignment: .leading, spacing: 8) {
                author
                StatusBadge(decisionLabel, tone: item.decisionTone)
                    .padding(.leading, 42)
            }
        }
    }

    private var decisionLabel: String {
        item.decision == "trade" ? L10n.string("Trade identified") : item.decisionTitle
    }

    private var author: some View {
        HStack(spacing: 10) {
            GuruMonogram(name: guruName ?? "?", size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(guruName ?? L10n.string("Unknown guru"))
                    .font(DesignTokens.personTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                postedAt
            }
        }
    }

    private var postedAt: some View {
        Text(Humanize.timestamp(item.sourceAt))
            .font(DesignTokens.caption)
            .foregroundStyle(Palette.tertiaryInk)
            .lineLimit(2)
    }

    private var understood: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Understood as"))
                .font(DesignTokens.caption.weight(.medium))
                .foregroundStyle(Palette.secondaryInk)
            if item.instructions.isEmpty {
                Text(item.headline)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(item.instructions.enumerated()), id: \.offset) { _, instruction in
                    Text(instruction.phrase)
                        .font(DesignTokens.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let reason = Reason.parserMessage(item.parserReason, needsReview: item.needsManualReview) {
                Text(reason)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.needsManualReview || item.isHistorical {
                actions
                    .padding(.top, 4)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("What each account did"))
                .font(DesignTokens.caption.weight(.medium))
                .foregroundStyle(Palette.secondaryInk)
            if item.destinations.isEmpty {
                // "Yet" only while the trade is still on its way to the accounts; once delivered with
                // no account attached, none will act on it.
                let waiting = item.decision == "trade" && item.deliveryStatus != "delivered"
                Label(
                    waiting
                        ? L10n.string("No account has acted on this post yet.")
                        : L10n.string("No account was asked to act on this post."),
                    systemImage: waiting ? "clock" : "minus.circle"
                )
                .font(.body)
                .foregroundStyle(.secondary)
            } else {
                ForEach(item.destinations) { destination in
                    DestinationResultView(destination: destination)
                }
            }
        }
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
        if let waiting = WaitingCall(item) {
            waitingActions(waiting)
        } else if item.needsManualReview {
            Button(L10n.string("Review and Correct…"), systemImage: "pencil.and.list.clipboard", action: review)
                .buttonStyle(.borderedProminent)
                .disabled(!canReview)
                .accessibilityHint(L10n.string("Opens the reviewed correction, preview, and confirmation workflow."))
        }
        evaluateButton
    }

    /// A call that waits for the owner (ADR-0007): copy it, or skip it, until its trading day ends.
    @ViewBuilder
    private func waitingActions(_ waiting: WaitingCall) -> some View {
        if skippedCalls.contains(item.sourceID) {
            Label(L10n.string("You skipped this call."), systemImage: "forward.end")
                .foregroundStyle(.secondary)
        } else if waiting.hasExpired(at: .now) {
            Label(L10n.string("This call expired when its trading day ended."), systemImage: "clock.badge.xmark")
                .foregroundStyle(.secondary)
        } else {
            Button(
                L10n.string(waiting.calls.isEmpty ? "Enter Trade…" : "Copy…"), systemImage: "doc.on.doc",
                action: { copy(waiting) }
            )
            .buttonStyle(.borderedProminent)
            .disabled(!canReview)
            .accessibilityIdentifier("activity.copy")
            .accessibilityHint(L10n.string("Opens the call to check, then previews the order in each waiting account."))
            Button(L10n.string("Skip"), systemImage: "forward") { skippedCalls.skip(item.sourceID) }
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
