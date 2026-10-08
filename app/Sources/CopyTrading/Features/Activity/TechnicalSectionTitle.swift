import SwiftUI

/// The name of one group in Technical details: "Timeline", "Order in primary", "Discord IDs".
struct TechnicalSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DesignTokens.activitySection)
            .foregroundStyle(Palette.secondaryInk)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
