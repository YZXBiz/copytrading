import SwiftUI

/// A screen section title in sentence case, with an optional trailing action.
struct SectionHeading<Accessory: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.string(title))
                .font(DesignTokens.sectionTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            accessory
        }
    }
}
