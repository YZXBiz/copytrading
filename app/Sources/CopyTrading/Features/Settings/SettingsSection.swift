import SwiftUI

/// A titled group of settings: a heading, an optional grey line under it,
/// and its rows in one soft rounded well with hairlines between them.
struct SettingsSection<Content: View>: View {
    var title: String?
    var subtitle: String?
    /// How far the hairlines between rows start from the leading edge; rows with an icon start
    /// them past it.
    var dividerInset: CGFloat = 14
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(L10n.string(title))
                            .font(DesignTokens.settingsHeading)
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let subtitle {
                        Text(L10n.string(subtitle))
                            .font(.body)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 4)
            }
            Group(subviews: content) { rows in
                if !rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Rectangle()
                                    .fill(contrast == .increased ? Palette.secondaryInk : Palette.hairline)
                                    .frame(height: 1 / displayScale)
                                    .padding(.leading, dividerInset)
                            }
                            row
                        }
                    }
                    .background(Palette.well, in: .rect(cornerRadius: 14, style: .continuous))
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}
