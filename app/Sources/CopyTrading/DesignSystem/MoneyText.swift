import SwiftUI

/// A dollar amount, or a signed change that always carries its sign, arrow, and color. A new value
/// rolls its digits into place, the way a trading screen ticks, unless motion is reduced or the
/// figure follows the pointer, where it must keep up with every move.
struct MoneyText: View {
    enum Style {
        case amount
        case change
    }

    let value: Decimal
    var style: Style = .amount
    var font: Font = .body
    /// Whole dollars for round figures such as a limit; cents when nil.
    var fractionDigits: Int? = nil
    /// Off where the figure follows the pointer, as a chart's readout does.
    var rolls = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(reduceMotion || !rolls ? nil : .smooth(duration: 0.35), value: value)
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .amount:
            Text(value.formatted(amountFormat))
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
                Text(value.formatted(.currency(code: "USD").sign(strategy: .always(showZero: false))))
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

    private var amountFormat: Decimal.FormatStyle.Currency {
        let currency = Decimal.FormatStyle.Currency(code: "USD")
        return fractionDigits.map { currency.precision(.fractionLength($0)) } ?? currency
    }
}
