import SwiftUI

/// A hand-drawn ground line across the width, with a small cloud and a pair of birds above it,
/// drawn in once from left to right. It is the stage an empty section stands on.
struct InkGround: View {
    var height: CGFloat = 64
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Self.ground(width: w, height: h)
                    .trim(from: 0, to: drawn)
                    .stroke(Palette.ink, style: InkStroke.style)
                Self.cloud(at: CGPoint(x: w * 0.22, y: h * 0.18))
                    .trim(from: 0, to: drawn)
                    .stroke(Palette.tertiaryInk, style: InkStroke.style)
                Self.birds(at: CGPoint(x: w * 0.68, y: h * 0.12))
                    .trim(from: 0, to: drawn)
                    .stroke(Palette.tertiaryInk, style: InkStroke.style)
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

    private static func cloud(at origin: CGPoint) -> Path {
        var path = Path()
        let x = origin.x
        let y = origin.y + 14
        path.move(to: CGPoint(x: x, y: y))
        path.addQuadCurve(to: CGPoint(x: x + 10, y: y - 8), control: CGPoint(x: x + 1, y: y - 9))
        path.addQuadCurve(to: CGPoint(x: x + 26, y: y - 9), control: CGPoint(x: x + 18, y: y - 20))
        path.addQuadCurve(to: CGPoint(x: x + 36, y: y), control: CGPoint(x: x + 37, y: y - 9))
        path.closeSubpath()
        return path
    }

    private static func birds(at origin: CGPoint) -> Path {
        var path = Path()
        for (dx, dy) in [(CGFloat(0), CGFloat(0)), (16, 5)] {
            let x = origin.x + dx
            let y = origin.y + dy
            path.move(to: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: x + 5, y: y), control: CGPoint(x: x + 2.5, y: y - 3.5))
            path.addQuadCurve(to: CGPoint(x: x + 10, y: y), control: CGPoint(x: x + 7.5, y: y - 3.5))
        }
        return path
    }
}
