import SwiftUI

/// A soft ring that keeps widening from the latest point while the balance is live, the way a
/// trading app shows a price is still moving. It stays still under Reduce Motion and while the
/// window is in the background, where nobody sees it and it would only cost battery.
struct LivePulse: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Circle()
            .fill(color.opacity(0.35))
            .frame(width: 9, height: 9)
            .phaseAnimator(reduceMotion || controlActiveState == .inactive ? [false] : [false, true]) { ring, expanded in
                ring
                    .scaleEffect(expanded ? 3 : 1)
                    .opacity(expanded ? 0 : 1)
            } animation: { expanded in
                expanded ? .easeOut(duration: 1.8) : nil
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
