import DesktopCore
import SwiftUI

/// A source-first inbox excerpt. Account identities and order evidence live in the reader.
struct ActivityInboxRow: View {
    let item: SourceActivity
    let guruName: String?
    let preview: String
    @ScaledMetric(relativeTo: .body) private var sourceSize = 14

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

            VStack(alignment: .leading, spacing: 4) {
                if item.needsManualReview && !item.outcomes.contains(where: { $0.outcome.tone == .caution }) {
                    Label(L10n.string("Needs review"), systemImage: "exclamationmark.bubble")
                        .foregroundStyle(StatusTone.caution.color)
                }
                if item.destinations.isEmpty {
                    if !item.needsManualReview {
                        Text(item.decisionTitle)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                } else {
                    // Keep every account's outcome visible; a failed or waiting account
                    // must never disappear behind another account's successful fill.
                    Text(outcomeText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
    }

    private var outcomeText: AttributedString {
        var result = AttributedString()
        for (index, entry) in item.outcomes.enumerated() {
            if index > 0 {
                var separator = AttributedString(" · ")
                separator.foregroundColor = Palette.tertiaryInk
                result += separator
            }
            if item.outcomes.count > 1 {
                // With more than one account, each outcome says whose it is.
                var account = AttributedString("\(entry.accountID) ")
                account.foregroundColor = Palette.secondaryInk
                result += account
            }
            var title = AttributedString(entry.outcome.title)
            title.foregroundColor = entry.outcome.tone.color
            result += title
        }
        return result
    }

    @MainActor private var timestamp: String {
        guard let date = item.sourceDate else { return "—" }
        return item.isToday
            ? date.formatted(.dateTime.hour().minute().locale(AppLanguagePreference.shared.language.locale))
            : date.formatted(
                .dateTime.month(.abbreviated).day().locale(AppLanguagePreference.shared.language.locale)
            )
    }
}
