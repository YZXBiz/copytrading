import DesktopCore
import SwiftUI

/// One post: who, what it asked for, when, and what each account did.
struct ActivityRow: View {
    let item: SourceActivity
    let guruName: String?
    let preview: String
    @ScaledMetric(relativeTo: .body) private var sourceSize = 14
    @ScaledMetric(relativeTo: .caption) private var authorSize = 12
    @ScaledMetric(relativeTo: .caption) private var timeSize = 11

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GuruMonogram(name: guruName ?? "?", size: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(guruName ?? L10n.string("Unknown guru"))
                        .font(.system(size: authorSize, weight: .semibold))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(time)
                        .font(.system(size: timeSize))
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                        .fixedSize()
                }

                Text(preview.isEmpty ? localizedMarkdown("No source text captured") : ActivitySourceText.formattedPreview(preview))
                    .font(.system(size: sourceSize))
                    .foregroundStyle(preview.isEmpty ? Palette.secondaryInk : Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(L10n.string("Understood as · %@", item.headline))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.destinations.isEmpty || item.needsManualReview {
                    VStack(alignment: .leading, spacing: 3) {
                        if item.needsManualReview && !item.outcomes.contains(where: { $0.outcome.tone == .caution }) {
                            let reviewOutcome = DestinationOutcome.needsReview(L10n.string("This post needs your review"))
                            Label(L10n.string("Needs review"), systemImage: reviewOutcome.symbol)
                                .foregroundStyle(reviewOutcome.tone.color)
                        }
                        ForEach(item.outcomes, id: \.accountID) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                if item.destinations.count > 1 {
                                    Text(entry.accountID)
                                        .foregroundStyle(Palette.tertiaryInk)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                                Label(entry.outcome.title, systemImage: entry.outcome.symbol)
                                    .foregroundStyle(entry.outcome.tone.color)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.caption)
                    .padding(.top, 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @MainActor private var time: String {
        guard let date = item.sourceDate else { return "—" }
        return Calendar.current.isDateInToday(date)
            ? date.formatted(.dateTime.hour().minute().locale(AppLanguagePreference.shared.language.locale))
            : date.formatted(
                .dateTime.month(.abbreviated).day().hour().minute().locale(AppLanguagePreference.shared.language.locale)
            )
    }
}
