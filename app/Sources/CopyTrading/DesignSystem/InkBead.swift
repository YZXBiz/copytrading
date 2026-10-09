import SwiftUI

/// A small solid ink dot that marks where something has got to on a drawn line: the step being
/// read, the order in flight, the next setup step. It bounces once each time `hop` changes, as
/// when an order fills, and is otherwise still. Nothing about it loops.
struct InkBead: View {
    /// Change it to make the bead bounce once.
    var hop = 0
    @State private var lift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Palette.ink)
            .frame(width: 10, height: 10)
            .offset(y: -lift)
            .onChange(of: hop) {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { lift = 8 } completion: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { lift = 0 }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
