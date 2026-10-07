import SwiftUI

/// The tour card's outline: a rounded card with a soft caret on its top or bottom edge, one shape
/// so the fill and stroke run unbroken around the caret.
struct SetupTourBubble: Shape {
    var caretX: CGFloat
    var caretOnTop: Bool
    var radius: CGFloat = 18

    var animatableData: CGFloat {
        get { caretX }
        set { caretX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let height: CGFloat = 9
        let halfWidth: CGFloat = 11
        let x = min(max(caretX, radius + halfWidth), rect.width - radius - halfWidth)
        let edge = caretOnTop ? rect.minY : rect.maxY
        let tip = caretOnTop ? edge - height : edge + height
        let inset: CGFloat = caretOnTop ? 0.5 : -0.5
        let bend: CGFloat = caretOnTop ? -1 : 1
        var caret = Path()
        caret.move(to: CGPoint(x: x - halfWidth, y: edge + inset))
        caret.addQuadCurve(to: CGPoint(x: x, y: tip), control: CGPoint(x: x - 3, y: edge + bend))
        caret.addQuadCurve(to: CGPoint(x: x + halfWidth, y: edge + inset), control: CGPoint(x: x + 3, y: edge + bend))
        caret.closeSubpath()
        return Path(roundedRect: rect, cornerRadius: radius, style: .continuous).union(caret)
    }
}
