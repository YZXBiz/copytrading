import SwiftUI

/// The name of one group in Technical details as a small label: "Timeline", "Order in primary",
/// "Discord IDs".
struct TechnicalSectionTitle: View {
    let text: String

    var body: some View {
        ActivityLabel(text: text, color: Palette.secondaryInk)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
