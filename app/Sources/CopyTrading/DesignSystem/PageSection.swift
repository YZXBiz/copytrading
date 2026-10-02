import SwiftUI

/// A titled section inside a `Page`: a compact semibold title, an optional quiet symbol, an
/// optional trailing accessory, then the content. It draws no frame of its own.
struct PageSection<Accessory: View, Content: View>: View {
    let title: String?
    let symbol: String?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        _ title: String? = nil,
        symbol: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.tertiaryInk)
                            .accessibilityHidden(true)
                    }
                    Text(L10n.string(title))
                        .font(DesignTokens.sectionTitle)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    accessory
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
