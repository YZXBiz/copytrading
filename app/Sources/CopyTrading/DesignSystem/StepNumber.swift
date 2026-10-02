import SwiftUI

/// A step's number in a soft accent disc, as the guide and the help popovers number their steps.
struct StepNumber: View {
    let number: Int

    var body: some View {
        Text(number, format: .number)
            .font(DesignTokens.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.tint)
            .frame(width: 20, height: 20)
            .background(Color.accentColor.opacity(0.12), in: .circle)
            .accessibilityHidden(true)
    }
}
