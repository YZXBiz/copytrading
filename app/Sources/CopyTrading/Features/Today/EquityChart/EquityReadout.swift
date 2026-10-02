import DesktopCore
import SwiftUI

/// The chart's headline, read in place so nothing floats over the curve: the window's change
/// at rest, the point under the pointer while scrubbing, or the move across a dragged span.
struct EquityReadout: View {
    let title: String
    let range: EquityHistoryRange
    let mode: EquityChartMode
    let curve: EquityCurve
    let stats: EquityCurveStats
    let accounts: [AccountSeries]
    let selection: EquitySelection

    private static let valueFont = Font.system(.largeTitle, design: .default, weight: .medium)

    private var focused: EquityCurvePoint? { selection.point.flatMap(curve.nearest(to:)) }
    private var measure: EquityCurveMeasure? {
        guard mode == .total else { return nil }
        return selection.span.flatMap { curve.measure(from: $0.start, to: $0.end) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(DesignTokens.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                switch mode {
                case .total: totalRow
                case .accounts: accountsRow
                }
            }
            .frame(minHeight: 58, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
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

    @ViewBuilder
    private var totalRow: some View {
        if let measure {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    MoneyText(value: Decimal(measure.change), style: .change, font: Self.valueFont)
                    percent(measure.changeFraction, change: measure.change)
                }
                Text(L10n.string("from %@ to %@", money(measure.start.value), money(measure.end.value)))
                    .font(DesignTokens.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            let point = focused ?? stats.last
            let change = point.value - stats.reference
            VStack(alignment: .leading, spacing: 5) {
                MoneyText(value: Decimal(point.value), font: Self.valueFont)
                    .foregroundStyle(Palette.ink)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        changeReadout(change)
                        Text(referenceName).font(DesignTokens.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        changeReadout(change)
                        Text(referenceName).font(DesignTokens.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func changeReadout(_ change: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MoneyText(value: Decimal(change), style: .change, font: DesignTokens.bodyText)
            percent(stats.reference == 0 ? nil : change / stats.reference, change: change)
        }
        // A figure is never shortened to "-$28…"; the row moves under the value instead.
        .fixedSize()
    }

    /// The legend doubles as the readout: each account's change now, or at the point being read.
    private var accountsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { accountItems }
            VStack(alignment: .leading, spacing: 4) { accountItems }
        }
    }

    private var accountItems: some View {
        ForEach(accounts) { account in
            let point = selection.point.flatMap(account.change.nearest(to:)) ?? account.change.points.last
            let dollars = selection.point.flatMap(account.equity.nearest(to:)) ?? account.equity.points.last
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Capsule()
                    .fill(account.color)
                    .frame(width: 12, height: 3)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    .accessibilityHidden(true)
                Text(account.name)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                if let point {
                    percent(point.value, change: point.value)
                        .font(DesignTokens.bodyEmphasis)
                }
                if let dollars {
                    Text(money(dollars.value))
                        .font(DesignTokens.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A signed percent in text ink; direction is carried by the sign, and by the arrow beside dollars.
    private func percent(_ fraction: Double?, change: Double) -> some View {
        Text(
            fraction.map {
                $0.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
            } ?? ""
        )
        .font(DesignTokens.bodyText)
        .monospacedDigit()
        .foregroundStyle(ChangeDirection(Decimal(change)).color)
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
