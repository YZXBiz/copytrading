import SwiftUI

/// A flat trace with three heartbeats across it: a small rise, a sharp spike and dip, a slow
/// swell. `progress` draws a short bright run of it ending there, for the sweep.
struct HeartbeatLine: Shape {
    /// The end of the bright run; nil draws the whole trace.
    var progress: Double?
    var runLength = 0.22

    var animatableData: Double {
        get { progress ?? 1 }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let trace = Self.trace(in: rect)
        guard let progress else { return trace }
        return trace.trimmedPath(from: max(0, progress - runLength), to: min(1, progress))
    }

    private static func trace(in rect: CGRect) -> Path {
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
