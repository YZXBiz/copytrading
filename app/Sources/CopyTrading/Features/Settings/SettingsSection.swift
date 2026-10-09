import SwiftUI

/// A titled group of settings: a heading in the display face, then its rows on the page with a
/// hairline only between rows. The heading and the space around it set the group apart, so no
/// line runs under the heading or after the last row.
struct SettingsSection<Content: View>: View {
    var title: String?
    var subtitle: String?
    /// How far the hairlines between rows start from the leading edge; rows with an icon start
    /// them past it.
    var dividerInset: CGFloat = 14
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

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
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                rule
                                    .padding(.leading, max(0, dividerInset - 14))
                            }
                            row
                                .padding(.horizontal, -14)
                        }
                    }
                }
            }
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(contrast == .increased ? Palette.secondaryInk : Palette.hairline)
            .frame(height: 1)
    }
}
