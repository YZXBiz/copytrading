import SwiftUI

/// The setup tour drawn over Connections: the target lit, the card beside it, and the strip at
/// the foot. The card sits under its target when there is room and above it otherwise, its caret
/// on the target's action for a row and on the field's start for a field.
struct SetupTourOverlay: View {
    let stop: SetupTourStop
    let targets: [SetupTourTarget: Anchor<CGRect>]
    @Bindable var model: AppModel
    @State private var cardHeight: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gap: CGFloat = 18
    private let margin: CGFloat = 16

    var body: some View {
        GeometryReader { layer in
            ZStack(alignment: .topLeading) {
                if let anchor = targets[stop.target] {
                    let hole = layer[anchor].insetBy(dx: -6, dy: -4)
                    let placement = place(around: hole, in: layer.size)
                    SetupTourSpotlight(hole: hole)
                    SetupTourCard(stop: stop, caretX: placement.caretX, caretOnTop: placement.below, model: model)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { cardHeight = $0 }
                        .offset(x: placement.origin.x, y: placement.origin.y)
                        .transition(.opacity)
                }
                SetupTourStrip(current: stop.step, progress: model.setupProgress)
                    .frame(width: layer.size.width, height: layer.size.height, alignment: .bottom)
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)
            }
            .frame(width: layer.size.width, height: layer.size.height, alignment: .topLeading)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: stop)
        }
    }

    /// Where the card goes for a target at `hole`, and where its caret points.
    private func place(around hole: CGRect, in size: CGSize) -> (origin: CGPoint, caretX: CGFloat, below: Bool) {
        let width = SetupTourCard.width
        let pointX = stop.pointsAtTrailingEdge ? hole.maxX - 50 : hole.minX + 60
        let x = min(max(pointX - width * (stop.pointsAtTrailingEdge ? 0.8 : 0.2), margin), size.width - width - margin)
        let fitsBelow = hole.maxY + gap + cardHeight + margin <= size.height
        let fitsAbove = hole.minY - gap - cardHeight >= margin
        let below = fitsBelow || !fitsAbove
        // A target taller than the room around it gets the card over its lower part.
        let y = below ? min(hole.maxY + gap, size.height - cardHeight - margin - 50) : hole.minY - gap - cardHeight
        return (CGPoint(x: x, y: y), pointX - x, below)
    }
}
