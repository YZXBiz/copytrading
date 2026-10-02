import SwiftUI

/// A dollar amount, or a signed change that always carries its sign, arrow, and color.
struct MoneyText: View {
    enum Style {
        case amount
        case change
    }

    let value: Decimal
    var style: Style = .amount
    var font: Font = .body

    var body: some View {
        switch style {
        case .amount:
            Text(value, format: .currency(code: "USD"))
                .font(font)
                .monospacedDigit()
                .contentTransition(.numericText(value: value.doubleValue))
        case .change:
            HStack(spacing: 4) {
                if direction != .flat {
                    Image(systemName: direction.symbol)
                        .imageScale(.small)
                        .fontWeight(.semibold)
                }
                Text(value, format: .currency(code: "USD").sign(strategy: .always(showZero: false)))
                    .contentTransition(.numericText(value: value.doubleValue))
            }
            .font(font)
            .monospacedDigit()
            .foregroundStyle(direction.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(direction.spoken(value))
        }
    }

    private var direction: ChangeDirection { ChangeDirection(value) }
}
