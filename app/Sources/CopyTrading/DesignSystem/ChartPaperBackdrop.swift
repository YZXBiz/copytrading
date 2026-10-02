import SwiftUI

/// CopyTrading's own backdrop, taken from its icon: a pale seafoam paper (the icon's navy in dark
/// mode) with a fine chart grid that fades away from `focus`. Reduce Transparency and increased
/// contrast leave only the paper. `RisingLineFlourish` draws the icon's line on it.
struct ChartPaperBackdrop: View {
    /// Where the grid is strongest, fading toward the edges.
    var focus = UnitPoint(x: 0.7, y: 0.1)
    var gridSpacing: CGFloat = 28
    /// Without paper, only the grid is drawn, over whatever is behind it.
    var paper = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var dark: Bool { colorScheme == .dark }

    private var paperColors: [Color] {
        dark
            ? [Color(red: 0.071, green: 0.098, blue: 0.153), Color(red: 0.09, green: 0.106, blue: 0.137)]
            : [Color(red: 0.855, green: 0.925, blue: 0.91), Color(red: 0.902, green: 0.929, blue: 0.941)]
    }

    var body: some View {
        LinearGradient(colors: paper ? paperColors : [.clear], startPoint: .top, endPoint: .bottom)
            .overlay {
                if !reduceTransparency && contrast != .increased {
                    GeometryReader { geometry in
                        grid
                            .mask {
                                RadialGradient(
                                    colors: [.black, .black.opacity(0.12)], center: focus, startRadius: 0,
                                    endRadius: max(geometry.size.width, geometry.size.height) * 0.75)
                            }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var grid: some View {
        Canvas { context, size in
            var lines = Path()
            var x = gridSpacing / 2
            while x < size.width {
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
                x += gridSpacing
            }
            var y = gridSpacing / 2
            while y < size.height {
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
                y += gridSpacing
            }
            let ink = dark ? Color.white.opacity(0.05) : Color(red: 0.12, green: 0.38, blue: 0.36).opacity(0.075)
            context.stroke(lines, with: .color(ink), lineWidth: 1)
        }
    }
}
