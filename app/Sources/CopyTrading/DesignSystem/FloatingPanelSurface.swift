import SwiftUI

/// Content treatment only: the native popover supplies the outer edge and shadow.
struct FloatingPanelSurface<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(title))
                    .font(DesignTokens.sectionTitle)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(L10n.string(subtitle))
                        .font(DesignTokens.caption)
                        .fontWeight(.regular)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Rectangle()
                .fill(contrast == .increased ? Palette.secondaryInk : Palette.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)

            content
                .font(DesignTokens.bodyText)
                .fontWeight(.regular)
                .foregroundStyle(Palette.ink)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            if reduceTransparency {
                Palette.page
            } else {
                Rectangle()
                    .fill(.regularMaterial)
                    .overlay(Palette.page.opacity(0.88))
            }
        }
    }
}
