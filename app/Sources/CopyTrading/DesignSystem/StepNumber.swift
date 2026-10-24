import SwiftUI

/// A step's number as two digits in ink ("01"), as the guide and the help popovers number
/// their steps. No disc around it.
struct StepNumber: View {
    let number: Int

    var body: some View {
        Text(String(format: "%02d", number))
            .font(DesignTokens.label)
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            .frame(minWidth: 22, alignment: .leading)
            .accessibilityHidden(true)
    }
}
