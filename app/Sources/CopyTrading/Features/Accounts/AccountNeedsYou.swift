import DesktopCore
import SwiftUI

/// The calls this account holds for the owner (ADR-0007), newest first, each a ticket with Copy and
/// Skip, until its trading day ends. Nothing shows when nothing waits.
struct AccountNeedsYou: View {
    let accountID: String
    let activity: [SourceActivity]
    let directory: GuruDirectory
    let skippedCalls: SkippedCalls
    let canCopy: Bool
    /// The page has no other ink capsule, so the newest call's Copy… takes it; every other Copy…
    /// is outlined.
    let ownsPrimaryAction: Bool
    let selectedPostID: SourceActivity.ID?
    /// The tickets sit in the side rail.
    let isCompact: Bool
    /// The call whose ticket or chart marker is under the pointer; each answers the other.
    @Binding var highlightedSourceID: String?
    let copy: (WaitingCall) -> Void
    /// Opens the post beside the page.
    let open: (WaitingCall) -> Void

    private var waiting: [WaitingCall] {
        Self.waiting(accountID: accountID, activity: activity, skippedCalls: skippedCalls, now: .now)
    }

    /// The calls this account waits on now: the one list the tickets and the chart's markers share.
    static func waiting(accountID: String, activity: [SourceActivity], skippedCalls: SkippedCalls, now: Date)
        -> [WaitingCall]
    {
        activity.compactMap {
            WaitingCall.open($0, skipped: skippedCalls.contains($0.sourceID), now: now)
        }.filter { $0.accountIDs.contains(accountID) }
    }

    var body: some View {
        // Ticks each second only while a skip can still be undone, so the line leaves on time;
        // otherwise once a minute, enough for a deadline's day word.
        TimelineView(.periodic(from: .now, by: skippedCalls.undoable() == nil ? 60 : 1)) { context in
            content(undo: skippedCalls.undoable(at: context.date), now: context.date)
        }
    }

    @ViewBuilder
    private func content(undo: (sourceID: String, text: String, at: Date)?, now: Date) -> some View {
        let waiting = self.waiting
        if !waiting.isEmpty || undo != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let undo {
                    undoLine(undo.text)
                }
                ForEach(Array(waiting.enumerated()), id: \.element.source.id) { index, call in
                    AccountCallTicket(
                        call: call,
                        guruName: directory.name(for: call.source.guruID),
                        canCopy: canCopy,
                        isPrimary: ownsPrimaryAction && index == 0,
                        isCompact: isCompact,
                        isFirst: index == 0,
                        isSelected: call.source.id == selectedPostID,
                        isHighlighted: highlightedSourceID == call.source.sourceID,
                        now: now,
                        hover: { highlightedSourceID = $0 ? call.source.sourceID : nil },
                        open: { open(call) },
                        copy: { copy(call) },
                        skip: { skippedCalls.skip(call.source.sourceID, text: call.source.readableText()) }
                    )
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
