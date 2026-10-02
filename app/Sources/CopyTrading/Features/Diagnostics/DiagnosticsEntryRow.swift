import DesktopCore
import SwiftUI

/// One journal record in the list: what happened, when, and how it ended.
struct DiagnosticsEntryRow: View {
    let entry: DiagnosticsJournalEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.symbol)
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(DesignTokens.rowTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(
                        entry.at.formatted(
                            Date.FormatStyle(
                                date: .omitted,
                                time: .standard,
                                locale: AppLanguagePreference.shared.language.locale
                            )
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
                    .fixedSize()
                }
                Label(entry.outcomeTitle, systemImage: entry.tone.symbol)
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                    .font(.caption)
                    .foregroundStyle(entry.tone == .caution ? entry.tone.color : Palette.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
