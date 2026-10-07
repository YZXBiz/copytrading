import SwiftUI

/// The setup tour drawn over Connections: the target lit, the card beside it, and the strip at
/// the foot. A field in a panel gets the card to its side, so the panel's own buttons stay in
/// view; a row gets it underneath, or above when there is no room, with the caret on its action.
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
                    // Inside a panel the hint sits under the field itself; the page gets the card.
                    if !stop.isInPanel {
                        SetupTourSpotlight(hole: hole)
                        SetupTourCard(stop: stop, caretEdge: placement.edge, caretOffset: placement.caret, model: model)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { cardHeight = $0 }
                            // A new stop fades in as a new card; its words never morph from the last.
                            .id(stop)
                            .transition(.opacity)
                            .offset(x: placement.origin.x, y: placement.origin.y)
                    }
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

    /// Where the card goes for a target at `hole`: its top-left corner, the edge its caret sits
    /// on, and how far along that edge the caret points.
    private func place(around hole: CGRect, in size: CGSize) -> (origin: CGPoint, edge: Edge, caret: CGFloat) {
        let width = SetupTourCard.width
        if !stop.pointsAtTrailingEdge, hole.maxX + gap + width + margin <= size.width {
            let y = min(max(hole.midY - 48, margin), size.height - cardHeight - margin)
            return (CGPoint(x: hole.maxX + gap, y: y), .leading, hole.midY - y)
        }
        let pointX = stop.pointsAtTrailingEdge ? hole.maxX - 50 : hole.minX + 60
        let x = min(max(pointX - width * (stop.pointsAtTrailingEdge ? 0.8 : 0.2), margin), size.width - width - margin)
        let fitsBelow = hole.maxY + gap + cardHeight + margin <= size.height
        let fitsAbove = hole.minY - gap - cardHeight >= margin
        if (fitsBelow && !(stop.prefersAbove && fitsAbove)) || !fitsAbove {
            // A target taller than the room around it gets the card over its lower part.
            let y = min(hole.maxY + gap, size.height - cardHeight - margin - 50)
            return (CGPoint(x: x, y: y), .top, pointX - x)
        }
        return (CGPoint(x: x, y: hole.minY - gap - cardHeight), .bottom, pointX - x)
    }
}
