import DesktopCore
import SwiftUI

/// The selected record on the page: its title, its fields under a hairline, then the redacted payload.
struct DiagnosticsEntryDetailView: View {
    let entry: DiagnosticsJournalEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.pageSectionSpacing) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.title)
                            .font(DesignTokens.listHeading)
                            .tracking(DesignTokens.listHeadingTracking)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 12)
                        StatusBadge(entry.outcomeTitle, tone: entry.tone)
                    }
                    Text(
                        entry.at.formatted(
                            Date.FormatStyle(
                                date: .abbreviated,
                                time: .standard,
                                locale: AppTime.locale,
                                timeZone: AppTime.zone
                            )
                        )
                    )
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        ForEach(entry.displayFields, id: \.label) { field in
                            GridRow {
                                Text(field.label)
                                    .foregroundStyle(Palette.tertiaryInk)
                                Text(field.value)
                                    .foregroundStyle(Palette.ink)
                                    .monospacedDigit()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.callout)
                    .textSelection(.enabled)
                }

                if let payload = entry.payloadJSON {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(L10n.string("Payload"))
                        Text(payload)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Palette.group, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
                            .accessibilityLabel(L10n.string("Redacted payload"))
                    }
                } else if entry.kind == .payload {
                    Callout(L10n.string("The payload was not kept: %@.", L10n.string(entry.outcomeTitle.lowercased())), tone: .caution)
                }
            }
            .frame(maxWidth: DesignTokens.readingContentMaxWidth, alignment: .leading)
            .padding(DesignTokens.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
