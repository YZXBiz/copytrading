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
        let waiting = self.waiting
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // One sentence, as a studio page would say it: how many wait, and until when.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(
                        waiting.count == 1
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
                VStack(spacing: 0) {
                    ForEach(Array(waiting.enumerated()), id: \.element.source.id) { index, call in
                        if index > 0 {
                            Hairline()
                        }
                        AccountNeedsYouRow(
                            call: call,
                            guruName: directory.name(for: call.source.guruID),
                            canCopy: canCopy,
                            isSelected: call.source.id == selectedPostID,
                            open: { open(call) },
                            copy: { copy(call) },
                            skip: { skippedCalls.skip(call.source.sourceID) }
                        )
                    }
                }
                .overlay(alignment: .top) { Hairline() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("account.needsYou")
        }
    }
}
