import SwiftUI

/// A small figure drawn in one ink line: a pebble of a body with two dots for eyes and two legs.
/// It takes a few steps when it appears, hops once each time `hop` changes, and then stands
/// still. Nothing about it loops.
struct InkWalker: View {
    /// Change it to make the walker hop once, as when an order fills.
    var hop = 0
    var color: Color = Palette.ink
    @State private var stride = false
    @State private var lift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            // Inset by half the pen so the outline is never cut at the canvas edge.
            let inset = InkStroke.width
            context.translateBy(x: inset, y: inset)
            let w = size.width - inset * 2
            let h = size.height - inset * 2
            let body = Path(ellipseIn: CGRect(x: w * 0.18, y: 0, width: w * 0.64, height: h * 0.72))
            context.fill(body, with: .color(Palette.page))
            context.stroke(body, with: .color(color), style: InkStroke.style)
            for x in [0.4, 0.6] {
                context.fill(
                    Path(ellipseIn: CGRect(x: w * x - 1.1, y: h * 0.3, width: 2.2, height: 2.6)),
                    with: .color(color))
            }
            let swing: CGFloat = stride ? 0.12 : -0.06
            var legs = Path()
            legs.move(to: CGPoint(x: w * 0.4, y: h * 0.7))
            legs.addLine(to: CGPoint(x: w * (0.3 - swing), y: h))
            legs.move(to: CGPoint(x: w * 0.6, y: h * 0.7))
            legs.addLine(to: CGPoint(x: w * (0.7 + swing), y: h))
            context.stroke(legs, with: .color(color), style: InkStroke.style)
        }
        .frame(width: 26, height: 31)
        .offset(y: -lift)
        .task {
            guard !reduceMotion else { return }
            for _ in 0..<6 {
                withAnimation(.easeInOut(duration: 0.18)) { stride.toggle() }
                try? await Task.sleep(for: .milliseconds(200))
            }
            withAnimation(.easeOut(duration: 0.18)) { stride = false }
        }
        .onChange(of: hop) {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                lift = 9
            } completion: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { lift = 0 }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
