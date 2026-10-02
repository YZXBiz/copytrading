import SwiftUI

/// An open panel's header on the app's chart paper, fading into the page below it, with the
/// icon's line in its trailing corner.
struct FloatingPanelHeaderBackdrop: View {
    var body: some View {
        ChartPaperBackdrop(focus: UnitPoint(x: 0.85, y: 0.3), gridSpacing: 18)
            .mask {
                LinearGradient(colors: [.black, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .trailing) {
                RisingLineFlourish(lineWidth: 1.8)
                    .frame(width: 84, height: 26)
                    .padding(.trailing, 22)
            }
            .background(Palette.page)
            .clipped()
    }
}
