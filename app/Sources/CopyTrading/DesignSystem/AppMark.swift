import SwiftUI

/// The app's mark, drawn the way the icon is: one ink line that dips, holds, and rises to a solid
/// dot, over a faint ground. It stands in for the icon wherever the name appears.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 600
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var ground = Path()
            ground.move(to: p(30, 520))
            ground.addCurve(to: p(570, 520), control1: p(200, 512), control2: p(400, 530))
            context.stroke(ground, with: .color(Palette.ink.opacity(0.3)), style: StrokeStyle(lineWidth: 26 * s, lineCap: .round))
            var line = Path()
            line.move(to: p(40, 360))
            line.addCurve(to: p(200, 410), control1: p(100, 360), control2: p(140, 426))
            line.addCurve(to: p(330, 310), control1: p(260, 394), control2: p(280, 300))
            line.addCurve(to: p(520, 110), control1: p(410, 322), control2: p(450, 130))
            context.stroke(
                line, with: .color(Palette.ink),
                style: StrokeStyle(lineWidth: 52 * s, lineCap: .round, lineJoin: .round))
            let r = 62 * s
            context.fill(Path(ellipseIn: CGRect(x: 520 * s - r, y: 110 * s - r, width: r * 2, height: r * 2)), with: .color(Palette.ink))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
