import SwiftUI

/// A small coloured dot for how an account's part of a post went; a glyph instead when the owner
/// asks to tell things apart without colour.
struct GuruOutcomeMark: View {
    let kind: GuruAccountOutcome.Kind
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor

    var body: some View {
        Group {
            if withoutColor {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
            } else {
                Circle()
                    .frame(width: 6, height: 6)
            }
        }
        .foregroundStyle(tint)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        switch kind {
        case .traded: .green
        case .notTraded: .orange
        case .waiting: Palette.amber
        case .working: Palette.accent
        case .settled: Palette.tertiaryInk
        }
    }

    private var symbol: String {
        switch kind {
        case .traded: "checkmark"
        case .notTraded: "nosign"
        case .waiting: "hourglass"
        case .working: "clock"
        case .settled: "circle"
        }
    }
}
