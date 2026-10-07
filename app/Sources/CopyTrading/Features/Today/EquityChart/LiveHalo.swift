import SwiftUI

/// A still, soft halo around the latest point while the balance is live, the way a trading app
/// marks a price that is still moving, without redrawing anything.
struct LiveHalo: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color.opacity(0.16))
            .overlay(Circle().strokeBorder(color.opacity(0.28), lineWidth: 1))
            .frame(width: 20, height: 20)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
