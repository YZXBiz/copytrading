import SwiftUI

/// The tour card's outline: a rounded card with a soft caret on the edge that faces its target,
/// one shape so the fill and stroke run unbroken around the caret.
struct SetupTourBubble: Shape {
    /// The card's edge the caret sits on: top, bottom, or leading.
    var edge: Edge
    /// Where along that edge the caret points, from the card's top-left corner.
    var offset: CGFloat
    var radius: CGFloat = 18

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let depth: CGFloat = 9
        let half: CGFloat = 11
        let card = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        var caret = Path()
        switch edge {
        case .top, .bottom:
            let x = min(max(offset, radius + half), rect.width - radius - half)
            let base = edge == .top ? rect.minY + 0.5 : rect.maxY - 0.5
            let tip = edge == .top ? rect.minY - depth : rect.maxY + depth
            let bend = edge == .top ? rect.minY - 1 : rect.maxY + 1
            caret.move(to: CGPoint(x: x - half, y: base))
            caret.addQuadCurve(to: CGPoint(x: x, y: tip), control: CGPoint(x: x - 3, y: bend))
            caret.addQuadCurve(to: CGPoint(x: x + half, y: base), control: CGPoint(x: x + 3, y: bend))
        case .leading, .trailing:
            let y = min(max(offset, radius + half), rect.height - radius - half)
            caret.move(to: CGPoint(x: rect.minX + 0.5, y: y - half))
            caret.addQuadCurve(to: CGPoint(x: rect.minX - depth, y: y), control: CGPoint(x: rect.minX - 1, y: y - 3))
            caret.addQuadCurve(to: CGPoint(x: rect.minX + 0.5, y: y + half), control: CGPoint(x: rect.minX - 1, y: y + 3))
        }
        caret.closeSubpath()
        return card.union(caret)
    }
}
