import SwiftUI

/// A rounded rectangle that grows from a card's bounds to the panel's own, so a Connections panel
/// opens out of the card that offered it. The panel sits centered in its layer, which places the
/// card in the panel's coordinates.
struct ConnectionMorphShape: Shape {
    /// The card's bounds in the layer's coordinates.
    let origin: CGRect
    let layer: CGSize
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let start = origin.offsetBy(dx: -(layer.width - rect.width) / 2, dy: -(layer.height - rect.height) / 2)
        let t = max(0, min(1, progress))
        let frame = CGRect(
            x: start.minX + (rect.minX - start.minX) * t,
            y: start.minY + (rect.minY - start.minY) * t,
            width: start.width + (rect.width - start.width) * t,
            height: start.height + (rect.height - start.height) * t
        )
        return Path(roundedRect: frame, cornerRadius: 20 + 6 * t, style: .continuous)
    }
}
