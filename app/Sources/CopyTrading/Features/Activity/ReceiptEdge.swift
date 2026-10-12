import SwiftUI

/// The torn zigzag at the foot of a printed receipt.
struct ReceiptEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let teeth = max(1, Int(rect.width / 12))
        let step = rect.width / CGFloat(teeth)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for tooth in 0..<teeth {
            let start = rect.minX + CGFloat(tooth) * step
            path.addLine(to: CGPoint(x: start + step / 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: start + step, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}
