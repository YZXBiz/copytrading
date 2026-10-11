import SwiftUI

/// One of the Sell sheet's parts of a lot (¼, ½, ¾, All) as a word in tracked capitals, no box:
/// the chosen one is marked in butter behind it and set in ink, the others wait in grey.
struct LotSaleShareChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovers = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(.title3, weight: .semibold))
                .tracking(DesignTokens.eyebrowTracking)
                .monospacedDigit()
                .foregroundStyle(isSelected || hovers ? Palette.ink : Palette.tertiaryInk)
                .markerHighlight(isSelected)
                .padding(.vertical, 6)
                .contentShape(.rect)
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { hovers = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
