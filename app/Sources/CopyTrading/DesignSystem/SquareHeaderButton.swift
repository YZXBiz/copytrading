import SwiftUI

/// A page-header control: a graphite symbol on a small white rounded square that lifts a
/// little on hover. Connections uses it for ⊕, Settings for close and back.
struct SquareHeaderButton: View {
    let title: String
    let symbol: String
    var fill = Palette.page
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            SquareControlLabel(symbol: symbol, isHovered: isHovered, fill: fill)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .help(L10n.string(title))
        .accessibilityLabel(L10n.string(title))
    }
}
