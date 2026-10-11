import DesktopCore
import SwiftUI

/// The chart's one-line readout, read in place so nothing floats over the curve: the window's
/// change at rest, the point under the pointer while scrubbing, or the move across a dragged span.
struct EquityReadout: View {
    let title: String
    let range: EquityHistoryRange
    let curve: EquityCurve
    let stats: EquityCurveStats
    let selection: EquitySelection

    private var focused: EquityCurvePoint? { selection.point.flatMap(curve.nearest(to:)) }
    private var measure: EquityCurveMeasure? {
        selection.span.flatMap { curve.measure(from: $0.start, to: $0.end) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(caption)
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
            figures
        }
        .font(DesignTokens.caption)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var figures: some View {
        if let measure {
            change(measure.change, fraction: measure.changeFraction)
        } else if let focused {
            Text(money(focused.value))
                .fontWeight(.medium)
                .foregroundStyle(Palette.ink)
            change(focused.value - stats.reference, fraction: fraction(of: focused.value - stats.reference))
        } else if range != .day {
            // A day's move already sits under the balance; longer windows say theirs here.
            change(stats.last.value - stats.reference, fraction: fraction(of: stats.last.value - stats.reference))
            Text(referenceName)
                .foregroundStyle(Palette.tertiaryInk)
        }
    }

    private var caption: String {
        if let measure {
            let from = EquityChartTime.point(measure.start.at, in: range)
            let to = EquityChartTime.point(measure.end.at, in: range)
            return L10n.string(
                "%@ → %@ · %@",
                from,
                to,
                EquityChartTime.duration(measure.duration, locale: AppLanguagePreference.shared.language.locale)
            )
        }
        if let focused { return EquityChartTime.point(focused.at, in: range) }
        if let at = selection.point { return EquityChartTime.point(at, in: range) }
        return title
    }

    private var referenceName: String {
        curve.baseline == nil ? L10n.string("since the start") : L10n.string("vs previous close")
    }

    private func fraction(of change: Double) -> Double? {
        stats.reference == 0 ? nil : change / stats.reference
    }

    /// Signed dollars and percent, coloured by direction; never shortened to "-$28…".
    private func change(_ change: Double, fraction: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            MoneyText(value: Decimal(change), style: .change, font: DesignTokens.caption.weight(.medium))
            if let fraction {
                Text(fraction.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false))))
                    .foregroundStyle(ChangeDirection(Decimal(change)).color)
            }
        }
        .fixedSize()
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
