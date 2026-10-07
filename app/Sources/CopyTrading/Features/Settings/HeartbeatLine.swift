import SwiftUI

/// A flat trace with three heartbeats across it: a small rise, a sharp spike and dip, a slow
/// swell.
struct HeartbeatLine: Shape {
    func path(in rect: CGRect) -> Path {
        // One beat as (x, y) in fractions of its slot; y grows downward from the baseline at 0.6.
        let beat: [(Double, Double)] = [
            (0, 0.6), (0.3, 0.6), (0.36, 0.48), (0.42, 0.6), (0.48, 0.6), (0.52, 0.72), (0.57, 0.08),
            (0.62, 0.92), (0.66, 0.6), (0.76, 0.6), (0.84, 0.44), (0.92, 0.6), (1, 0.6),
        ]
        let beats = 3
        var path = Path()
        for index in 0..<beats {
            let slot = rect.width / CGFloat(beats)
            for (pointIndex, point) in beat.enumerated() {
                let location = CGPoint(
                    x: rect.minX + slot * CGFloat(index) + slot * point.0, y: rect.minY + rect.height * point.1)
                if index == 0 && pointIndex == 0 { path.move(to: location) } else { path.addLine(to: location) }
            }
        }
        return path
    }
}
