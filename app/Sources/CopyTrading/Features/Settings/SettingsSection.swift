import SwiftUI

/// A titled group of settings: a heading in the display face, then its rows in one bordered box
/// with a hairline between each, as the sheets group theirs (`SheetGroup`). What the group is for
/// is a tooltip on the heading, not a line under it.
struct SettingsSection<Content: View>: View {
    var title: String?
    var hint: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(L10n.string(title))
                    .font(DesignTokens.settingsHeading)
                    .tracking(DesignTokens.listHeadingTracking)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .help(hint.map { L10n.string($0) } ?? "")
                    .accessibilityHint(hint.map { L10n.string($0) } ?? "")
            }
            Group(subviews: content) { rows in
                if !rows.isEmpty {
                    // Rows carry their own inset, so the box adds none.
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            if row.id != rows.first?.id {
                                Rectangle()
                                    .fill(Palette.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, DesignTokens.sheetRowInset)
                            }
                            row
                        }
                    }
                    .background(Palette.page)
                    .clipShape(.rect(cornerRadius: DesignTokens.sheetGroupRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.sheetGroupRadius)
                            .strokeBorder(Palette.hairline)
                    }
                }
            }
        }
    }

}
