import SwiftUI

/// Buy or Sell, the one choice the trade turns on: the chosen side in the display face on a
/// butter capsule, the other quiet beside it.
struct TradeSideSwitch: View {
    let isSell: Bool
    let choose: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            side(L10n.string("Buy"), isOn: !isSell) { choose(false) }
                .accessibilityIdentifier("review.buy")
            side(L10n.string("Sell"), isOn: isSell) { choose(true) }
                .accessibilityIdentifier("review.sell")
        }
    }

    private func side(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DisplayFont.font(size: 24, weight: isOn ? .medium : .regular, relativeTo: .title))
                // Butter is light in both themes, so the chosen word stays dark ink on it.
                .foregroundStyle(isOn ? Color(white: 0.12) : Palette.tertiaryInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
                .background(Capsule().fill(Palette.butter).opacity(isOn ? 1 : 0))
                .contentShape(.capsule)
        }
        .buttonStyle(QuietPressButtonStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
