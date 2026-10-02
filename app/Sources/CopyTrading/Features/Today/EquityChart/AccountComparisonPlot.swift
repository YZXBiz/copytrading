import Charts
import DesktopCore
import SwiftUI

/// Each account's change from its own reference on one percent scale, so accounts of any size compare.
struct AccountComparisonPlot: View {
    let series: [AccountSeries]
    let range: EquityHistoryRange
    @Binding var selection: EquitySelection
    @Environment(\.colorSchemeContrast) private var contrast

    private var allPoints: [EquityCurvePoint] { series.flatMap(\.change.points) }

    private var scale: EquityChartScale {
        let times = allPoints.map(\.at)
        let first = times.min() ?? .now
        return EquityChartScale(range: range, first: first, last: times.max() ?? first)
    }

    private var valueRange: (lower: Double, upper: Double) {
        let values = allPoints.map(\.value) + [0]
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let margin = max((high - low) * 0.16, 0.0005)
        return (low - margin, high + margin)
    }

    var body: some View {
        let bounds = valueRange
        let axis = EquityValueAxis(lower: bounds.lower, upper: bounds.upper, count: 3)
        let scale = self.scale
        let ticks = scale.ticks
        let focused = selection.point
        Chart {
            RuleMark(y: .value("No change", 0))
                .foregroundStyle(contrast == .increased ? Palette.secondaryInk : Palette.tertiaryInk.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .accessibilityHidden(true)
            ForEach(series) { account in
                ForEach(EquityLineRun.runs(account.change.points, on: scale)) { run in
                    ForEach(run.points, id: \.at) { point in
                        line(through: point, of: account, in: run, on: scale, axis: axis)
                    }
                }
                if let last = account.change.points.last {
                    PointMark(x: .value("Time", scale.x(last.at)), y: .value("Change", last.value))
                        .symbolSize(38)
                        .foregroundStyle(account.color)
                        .accessibilityHidden(true)
                }
            }
            if let focused {
                RuleMark(x: .value("Time", scale.x(focused)))
                    .foregroundStyle(Palette.secondaryInk.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)
                ForEach(series) { account in
                    if let point = account.change.nearest(to: focused) {
                        ringedDot(at: point, color: account.color, on: scale)
                    }
                }
            }
        }
        .chartXScale(domain: xDomain(on: scale), range: .plotDimension(startPadding: 4, endPadding: 14))
        .chartYScale(domain: bounds.lower...bounds.upper)
        .chartXAxis {
            AxisMarks(values: ticks.map(\.x).filter { xDomain(on: scale).contains($0) }) { value in
                AxisValueLabel(collisionResolution: .greedy) {
                    if let x = value.as(Double.self), let tick = ticks.first(where: { abs($0.x - x) < 1e-9 }) {
                        Text(tick.label)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: axis.ticks) { value in
                AxisValueLabel(horizontalSpacing: 6) {
                    if let fraction = value.as(Double.self) {
                        Text(axis.percent(fraction))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.background {
                ChartPaperBackdrop(focus: UnitPoint(x: 0.85, y: 0.3), gridSpacing: 24, paper: false)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
            }
        }
        .chartOverlay { proxy in
            EquityPointerLayer(proxy: proxy, scale: scale, selection: $selection, measures: false)
        }
    }

    /// A day fills the width from its first point to a little past the latest, as the total does.
    private func xDomain(on scale: EquityChartScale) -> ClosedRange<Double> {
        let times = allPoints.map(\.at)
        guard scale.isDay, let first = times.min(), let last = times.max() else { return 0...1 }
        let start = scale.x(first)
        let end = scale.x(max(last, first.addingTimeInterval(3_600)))
        return start...max(end, start + 0.05)
    }

    /// One point of an account's line, kept out of `body` so the chart builder type-checks quickly.
    @ChartContentBuilder
    private func line(
        through point: EquityCurvePoint, of account: AccountSeries, in run: EquityLineRun, on scale: EquityChartScale,
        axis: EquityValueAxis
    ) -> some ChartContent {
        let width: CGFloat = contrast == .increased ? 2.75 : 2.25
        let label = L10n.string("%@, %@", account.name, EquityChartTime.point(point.at, in: range))
        LineMark(
            x: .value("Time", scale.x(point.at)),
            y: .value("Change", point.value),
            series: .value("Account", "\(account.id)-\(run.id)")
        )
        .foregroundStyle(account.color.opacity(run.isExtended ? 0.45 : 1))
        .interpolationMethod(.monotone)
        .lineStyle(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        .accessibilityLabel(label)
        .accessibilityValue(axis.percent(point.value))
    }

    @ChartContentBuilder
    private func ringedDot(at point: EquityCurvePoint, color: Color, on scale: EquityChartScale) -> some ChartContent {
        PointMark(x: .value("Time", scale.x(point.at)), y: .value("Change", point.value))
            .symbolSize(120)
            .foregroundStyle(Palette.page)
            .accessibilityHidden(true)
        PointMark(x: .value("Time", scale.x(point.at)), y: .value("Change", point.value))
            .symbolSize(50)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
