import SwiftUI

/// A titled group of settings: a heading in the display face, then its rows on the page, parted by
/// space alone. No line runs anywhere in the group.
struct SettingsSection<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 5) {
                    if let title {
                        Text(L10n.string(title))
                            .font(DesignTokens.settingsHeading)
                            .tracking(DesignTokens.listHeadingTracking)
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let subtitle {
                        Text(L10n.string(subtitle))
                            .font(.body)
                            .foregroundStyle(Palette.tertiaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Group(subviews: content) { rows in
                if !rows.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(rows) { row in
                            row
                                .padding(.horizontal, -14)
                        }
                    }
                }
            }
        }
    }

}
