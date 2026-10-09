import SwiftUI

/// A hand-drawn ground line across the width, drawn in once from left to right.
struct InkGround: View {
    var height: CGFloat = 16
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Self.ground(width: w, height: h)
                    .trim(from: 0, to: drawn)
                    // Quiet: the ground sets the scene, it is not the subject.
                    .stroke(Palette.ink.opacity(0.3), style: InkStroke.style)
            }
        }
        .frame(height: height)
        .onAppear {
            guard !reduceMotion else {
                drawn = 1
                return
            }
            withAnimation(.easeInOut(duration: 1.4)) { drawn = 1 }
        }
        .accessibilityHidden(true)
    }

    /// Nearly level, with the small wobble of a line drawn without a ruler.
    private static func ground(width w: CGFloat, height h: CGFloat) -> Path {
        var path = Path()
        let y = h - 2
        path.move(to: CGPoint(x: 0, y: y))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: y - 1.5), control1: CGPoint(x: w * 0.18, y: y + 1.2),
            control2: CGPoint(x: w * 0.34, y: y - 2))
        path.addCurve(
            to: CGPoint(x: w, y: y), control1: CGPoint(x: w * 0.66, y: y - 1),
            control2: CGPoint(x: w * 0.84, y: y + 1.5))
        return path
    }
}
