import SwiftUI

/// The name of one group in Technical details in tracked capitals: "TIMELINE", "ORDER IN PRIMARY",
/// "DISCORD IDS".
struct TechnicalSectionTitle: View {
    let text: String

    var body: some View {
        ActivityLabel(text: text, color: Palette.secondaryInk)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
