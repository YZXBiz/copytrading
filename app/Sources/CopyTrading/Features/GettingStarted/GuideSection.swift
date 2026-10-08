import SwiftUI

/// A heading and what follows it, as one section of the guide document.
struct GuideSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string(title))
                .font(DesignTokens.documentHeading)
                .tracking(DesignTokens.listHeadingTracking)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
