import DesktopCore
import SwiftUI

/// A source-first inbox excerpt with how the post ended and, when several accounts are in view,
/// which ones it reached. Order evidence lives in the reader.
struct ActivityInboxRow: View {
    let item: SourceActivity
    let guruName: String?
    let preview: String
    var showsAccounts = false
    @ScaledMetric(relativeTo: .body) private var sourceSize = 14
    @Environment(SkippedCalls.self) private var skippedCalls: SkippedCalls?
    @Environment(\.postProgressContext) private var progressContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                GuruMonogram(name: guruName ?? "?", size: 20)
                Text(guruName ?? L10n.string("Unknown guru"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(timestamp)
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
                    .fixedSize()
            }

            Text(preview.isEmpty ? localizedMarkdown("No message text") : ActivitySourceText.formattedPreview(preview))
                .font(.system(size: sourceSize))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // How the post ended, in the card's words (ADR-0007).
            let outcome = ActivityCardOutcome(item, skipped: skippedCalls?.contains(item.sourceID) == true)
            HStack(spacing: 8) {
                if let progress = PostProgress(item, context: progressContext) {
                    PostProgressLabel(progress: progress, compact: true)
                } else {
                    Label(outcome.title, systemImage: outcome.tone.symbol)
                        .foregroundStyle(outcome.tone.color)
                }
                if showsAccounts, !item.destinations.isEmpty {
                    Text(item.destinations.map(\.accountID).joined(separator: ", "))
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }
            }
            .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
    }

    @MainActor private var timestamp: String {
        guard let date = item.sourceDate else { return "—" }
        return item.isToday
            ? date.formatted(AppTime.style(.dateTime.hour().minute().second()))
            : date.formatted(
                AppTime.style(.dateTime.month(.abbreviated).day())
            )
    }
}
