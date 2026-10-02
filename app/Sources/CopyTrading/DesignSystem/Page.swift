import SwiftUI

/// Arranges sections on the continuous workspace with space and hairlines instead of a page card.
struct Page<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.pageSectionSpacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
