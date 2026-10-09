import SwiftUI

/// The line a field writes on: round dots at rest, a blank to fill in that can never be mistaken
/// for a rule between sections, and a solid ink line while the field is being typed in.
struct WritingLine: View {
    var isActive = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            var line = Path()
            line.move(to: CGPoint(x: 0.75, y: size.height / 2))
            line.addLine(to: CGPoint(x: size.width - 0.75, y: size.height / 2))
            if isActive {
                context.stroke(line, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            } else {
                context.stroke(line, with: .color(rest), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0, 3.5]))
            }
        }
        .frame(height: 1.5)
        .animation(.easeOut(duration: 0.15), value: isActive)
        .accessibilityHidden(true)
    }

    private var rest: Color {
        contrast == .increased ? Palette.secondaryInk : Palette.tertiaryInk.opacity(0.55)
    }
}
