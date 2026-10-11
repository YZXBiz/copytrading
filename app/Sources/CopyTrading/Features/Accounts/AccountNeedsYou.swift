import DesktopCore
import SwiftUI

/// The calls this account holds for the owner (ADR-0007), newest first, each with Copy and Skip,
/// until its trading day ends. Nothing shows when nothing waits.
struct AccountNeedsYou: View {
    let accountID: String
    let activity: [SourceActivity]
    let directory: GuruDirectory
    let skippedCalls: SkippedCalls
    let canCopy: Bool
    let selectedPostID: SourceActivity.ID?
    let copy: (WaitingCall) -> Void
    /// Opens the post beside the page.
    let open: (WaitingCall) -> Void

    private var waiting: [WaitingCall] {
        let now = Date.now
        return activity.compactMap(WaitingCall.init).filter {
            $0.accountIDs.contains(accountID) && !$0.hasExpired(at: now) && !skippedCalls.contains($0.source.sourceID)
        }
    }

    var body: some View {
        // Ticks each second only while a skip can still be undone, so the line leaves on time.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(undo: skippedCalls.undoable(at: context.date))
        }
    }

    @ViewBuilder
    private func content(undo: (sourceID: String, text: String, at: Date)?) -> some View {
        let waiting = self.waiting
        if !waiting.isEmpty || undo != nil {
            VStack(alignment: .leading, spacing: 12) {
                // One sentence, as a studio page would say it: how many wait, and until when.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(
                        waiting.isEmpty
                            ? L10n.string("Nothing else is waiting")
                            : waiting.count == 1
                                ? L10n.string("One call is waiting for you")
                                : L10n.string("%lld calls are waiting for you", Int64(waiting.count))
                    )
                    .font(DesignTokens.listHeading)
                    .tracking(DesignTokens.listHeadingTracking)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    if let deadline = waiting.compactMap(\.deadline).min() {
                        Text(L10n.string("Copy by %@", TradingDeadlineText.text(deadline, now: .now)))
                            .font(DesignTokens.lede)
                            .tracking(DesignTokens.ledeTracking)
                            .foregroundStyle(Palette.amber)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    if let undo {
                        undoLine(undo.text)
                    }
                    ForEach(Array(waiting.enumerated()), id: \.element.source.id) { index, call in
                        AccountNeedsYouRow(
                            call: call,
                            guruName: directory.name(for: call.source.guruID),
                            canCopy: canCopy,
                            isSelected: call.source.id == selectedPostID,
                            open: { open(call) },
                            copy: { copy(call) },
                            skip: { skippedCalls.skip(call.source.sourceID, text: call.source.readableText()) }
                        )
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("account.needsYou")
        }
    }

    /// Where the skipped call was, for a few seconds: what was skipped, and Undo.
    private func undoLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text.isEmpty ? L10n.string("Skipped") : L10n.string("Skipped “%@”", text))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
            Button(L10n.string("Undo")) { skippedCalls.undo() }
                .buttonStyle(QuietTextButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityIdentifier("account.needsYou.undo")
        }
        .padding(.vertical, 10)
        .transition(.opacity)
    }
}
