import DesktopCore
import SwiftUI

/// The selected record on a white reading surface: its fields, then the redacted payload.
struct DiagnosticsEntryDetailView: View {
    let entry: DiagnosticsJournalEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.pageSectionSpacing) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(entry.title, systemImage: entry.symbol)
                            .font(DesignTokens.sectionTitle)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 12)
                        StatusBadge(entry.outcomeTitle, tone: entry.tone)
                    }
                    Text(
                        entry.at.formatted(
                            Date.FormatStyle(
                                date: .abbreviated,
                                time: .standard,
                                locale: AppLanguagePreference.shared.language.locale
                            )
                        )
                    )
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        ForEach(entry.displayFields, id: \.label) { field in
                            GridRow {
                                Text(field.label)
                                    .foregroundStyle(.secondary)
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
                .padding(DesignTokens.workingSurfacePadding)
                .background(Palette.page, in: .rect(cornerRadius: DesignTokens.readingCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.readingCornerRadius)
                        .strokeBorder(Palette.hairline, lineWidth: 0.7)
                        .allowsHitTesting(false)
                }

                if let payload = entry.payloadJSON {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("Payload"))
                            .font(DesignTokens.sectionTitle)
                            .foregroundStyle(Palette.ink)
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
