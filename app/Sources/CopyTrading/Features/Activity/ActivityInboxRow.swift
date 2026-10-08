import DesktopCore
import SwiftUI

/// A source-first inbox excerpt with how the post ended. Account identities and order evidence
/// live in the reader.
struct ActivityInboxRow: View {
    let item: SourceActivity
    let guruName: String?
    let preview: String
    @ScaledMetric(relativeTo: .body) private var sourceSize = 14
    @Environment(SkippedCalls.self) private var skippedCalls: SkippedCalls?

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
            Label(outcome.title, systemImage: outcome.tone.symbol)
                .foregroundStyle(outcome.tone.color)
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
