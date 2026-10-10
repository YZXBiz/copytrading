import SwiftUI

/// The top of a screen: its name in the display face with a quiet lede line under it, and the
/// page's own controls at the trailing edge.
struct PageHeadline<Trailing: View>: View {
    let title: String
    var lede: String?
    @ViewBuilder let trailing: Trailing

    init(_ title: String, lede: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.lede = lede
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(DesignTokens.pageTitle)
                    .tracking(DesignTokens.entityTitleTracking)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let lede {
                    Text(lede)
                        .font(DesignTokens.lede)
                        .tracking(DesignTokens.ledeTracking)
                        .foregroundStyle(Palette.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
                .padding(.top, 8)
        }
    }
}
