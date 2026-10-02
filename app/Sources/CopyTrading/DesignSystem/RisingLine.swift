import SwiftUI

/// The line from CopyTrading's icon: a flat start, a dip and a spike, then a climb to the right.
/// The icon, the appearance thumbnails, and the chart-paper backdrop all draw it.
struct RisingLine: Shape {
    /// Where the line ends, as a fraction of its frame, for the dot drawn on its tip.
    static let tip = UnitPoint(x: 1, y: 0.05)

    func path(in rect: CGRect) -> Path {
        let points: [(Double, Double)] = [
            (0, 0.62), (0.18, 0.62), (0.3, 0.2), (0.42, 0.85), (0.55, 0.55), (0.68, 0.66), (1, 0.05),
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let location = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        return path
    }
}
