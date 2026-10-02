import SwiftUI

extension View {
    /// A header bar over a scrolling screen, drawn on the canvas. Titles sit on the canvas with no
    /// darker band or edge line under them, so the system scroll-edge effect is off at the top.
    func pageBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        safeAreaBar(edge: .top, spacing: 0) {
            bar().background(Palette.canvas)
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }
}
