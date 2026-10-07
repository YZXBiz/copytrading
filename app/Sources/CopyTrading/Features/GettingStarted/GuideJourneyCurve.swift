import CoreGraphics

/// Where the journey's stops sit in a diagram of a given width, and the soft curve between two of
/// them: each leg leaves and arrives level, so the path reads as one gentle wave.
struct GuideJourneyCurve {
    let width: CGFloat
    let count: Int

    /// Alternating heights give the wave; the pattern repeats past six stops.
    private static let heights: [CGFloat] = [62, 86, 58, 84, 60, 86]

    func point(_ index: Int) -> CGPoint {
        CGPoint(
            x: width * (CGFloat(index) + 0.5) / CGFloat(count),
            y: Self.heights[index % Self.heights.count])
    }

    /// The point `fraction` of the way along the leg from stop `index` to the next.
    func point(onLeg index: Int, at fraction: CGFloat) -> CGPoint {
        let (a, c1, c2, b) = controls(index)
        let t = fraction
        let u = 1 - t
        let x = u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x
        let y = u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y
        return CGPoint(x: x, y: y)
    }

    func controls(_ index: Int) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        let a = point(index)
        let b = point(index + 1)
        let half = (b.x - a.x) / 2
        return (a, CGPoint(x: a.x + half, y: a.y), CGPoint(x: b.x - half, y: b.y), b)
    }
}
