import CoreGraphics

/// Where an open Connections panel sits. Centered on the page, or, while the assistant is open over
/// the page's trailing side, centered in the room beside it, narrower when that room is tight, so
/// the two never cover each other.
struct ConnectionPanelPlacement: Equatable {
    static let fullWidth: CGFloat = 420
    static let narrowest: CGFloat = 300
    static let margin: CGFloat = 12

    let width: CGFloat
    let centerX: CGFloat

    /// `coveredTrailing` is how much of the page's trailing side something above it covers.
    init(pageWidth: CGFloat, coveredTrailing: CGFloat) {
        let room = max(pageWidth - coveredTrailing, 0)
        width = min(Self.fullWidth, max(Self.narrowest, room - 2 * Self.margin))
        centerX = max(room / 2, Self.margin + width / 2)
    }

    var minX: CGFloat { centerX - width / 2 }
    var maxX: CGFloat { centerX + width / 2 }
}
