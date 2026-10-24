import SwiftUI

/// A dollar amount, or a signed change that always carries its sign, arrow, and color. A new value
/// rolls its digits into place, the way a trading screen ticks, unless motion is reduced or the
/// figure follows the pointer, where it must keep up with every move. Digits are always tabular, so
/// a column of amounts lines up and a ticking figure never shifts its neighbours.
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
    /// A page's one big figure steps its cents down to this smaller grey face, as a statement
    /// prints a balance: "$102,486" then ".37".
    var centsFont: Font? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(reduceMotion || !rolls ? nil : .smooth(duration: 0.35), value: value)
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .amount:
            let text = value.formatted(amountFormat)
            if let centsFont, let split = Self.split(text) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(split.whole)
                        .font(font)
                        .contentTransition(.numericText(value: value.doubleValue))
                    Text(split.cents)
                        .font(centsFont)
                        .foregroundStyle(Palette.tertiaryInk)
                        .contentTransition(.numericText(value: value.doubleValue))
                }
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
            } else {
                Text(text)
                    .font(font)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value.doubleValue))
            }
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

    /// A formatted amount at its decimal point: "$102,486" and ".37". Nil without one.
    static func split(_ text: String) -> (whole: String, cents: String)? {
        let separator = Locale.current.decimalSeparator ?? "."
        guard let point = text.range(of: separator, options: .backwards) else { return nil }
        return (String(text[..<point.lowerBound]), String(text[point.lowerBound...]))
    }
}
