import Charts
import DesktopCore
import SwiftUI

/// The combined curve, drawn on the app's chart paper: one smooth line in the day's color over a
/// soft wash, filling the width from its first point to now, and an axis tag while reading a point
/// or span.
struct EquityPlot: View {
    let curve: EquityCurve
    let stats: EquityCurveStats
    let range: EquityHistoryRange
    @Binding var selection: EquitySelection
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption) private var valueAxisWidth = 84

    private var reference: Double { stats.reference }
    private var scale: EquityChartScale { EquityChartScale(range: range, first: stats.open.at, last: stats.last.at) }
    private var focused: EquityCurvePoint? { selection.point.flatMap(curve.nearest(to:)) }
    private var measure: EquityCurveMeasure? { selection.span.flatMap { curve.measure(from: $0.start, to: $0.end) } }

    /// The whole line takes the day's direction: green when it ends above its reference, red below,
    /// grey when it has not moved. Crossings stay readable against the dotted reference.

    private func tone(_ value: Double) -> Color {
        value > reference ? EquityTone.of(true) : value < reference ? EquityTone.of(false) : Palette.tertiaryInk
    }

    /// The latest point is the balance just read, so it pulses while the day is still being written.

    private var valueRange: (lower: Double, upper: Double) {
        let low = min(stats.low.value, reference)
        let high = max(stats.high.value, reference)
        let margin = max((high - low) * 0.16, 1)
        return (low - margin, high + margin)
    }

    /// The value the axis tag shows: the point being read, else the latest.
    private var tagged: EquityCurvePoint { focused ?? measure?.end ?? stats.last }

    var body: some View {
        let bounds = valueRange
        let axis = EquityValueAxis(lower: bounds.lower, upper: bounds.upper, count: 3)
        let scale = self.scale
        let ticks = scale.ticks
        let runs = EquityLineRun.runs(curve.points, on: scale)
        Chart {
            referenceLine
            ForEach(runs) { run in
                ForEach(run.points, id: \.at) { point in
                    LineMark(
                        x: .value("Time", scale.x(point.at)),
                        y: .value("Equity", point.value),
                        series: .value("Run", run.id)
                    )
                    .foregroundStyle(Palette.ink.opacity(run.isExtended ? 0.35 : 1))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: contrast == .increased ? 2.25 : 1.75, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(EquityChartTime.point(point.at, in: range))
                    .accessibilityValue(point.value.formatted(.currency(code: "USD")))
                }
            }
            measureMarks(on: scale)
            focusMarks(on: scale)
            PointMark(x: .value("Time", scale.x(stats.last.at)), y: .value("Equity", stats.last.value))
                .symbolSize(30)
                .foregroundStyle(Palette.ink)
                .accessibilityHidden(true)
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
            AxisMarks(position: .trailing, values: axis.ticks(clearOf: selection == .none ? nil : tagged.value)) { value in
                AxisValueLabel(horizontalSpacing: 6) {
                    if let amount = value.as(Double.self) {
                        Text(axis.money(amount))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(minWidth: valueAxisWidth, alignment: .leading)
                    }
                }
            }
            if selection != .none {
                AxisMarks(position: .trailing, values: [tagged.value]) { _ in
                    AxisValueLabel(horizontalSpacing: 6) {
                        ValueTag(text: tagged.value.formatted(.currency(code: "USD")), color: tone(tagged.value))
                            .frame(minWidth: valueAxisWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            EquityPointerLayer(proxy: proxy, scale: scale, selection: $selection, measures: true)
        }
    }

    @ChartContentBuilder
    private var referenceLine: some ChartContent {
        RuleMark(y: .value(curve.baseline == nil ? "Start" : "Previous close", reference))
            .foregroundStyle(contrast == .increased ? Palette.secondaryInk : Palette.tertiaryInk.opacity(0.75))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            .accessibilityLabel(curve.baseline == nil ? "Start" : "Previous close")
            .accessibilityValue(reference.formatted(.currency(code: "USD")))
    }

    @ChartContentBuilder
    private func measureMarks(on scale: EquityChartScale) -> some ChartContent {
        if let measure {
            let tone = EquityTone.of(change: measure.change)
            RectangleMark(xStart: .value("From", scale.x(measure.start.at)), xEnd: .value("To", scale.x(measure.end.at)))
                .foregroundStyle(tone.opacity(0.08))
                .accessibilityHidden(true)
            ForEach([measure.start, measure.end], id: \.at) { point in
                RuleMark(x: .value("Time", scale.x(point.at)))
                    .foregroundStyle(tone.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)
            }
            ringedDot(at: measure.start, on: scale)
            ringedDot(at: measure.end, on: scale)
        }
    }

    @ChartContentBuilder
    private func focusMarks(on scale: EquityChartScale) -> some ChartContent {
        if let focused {
            RuleMark(x: .value("Time", scale.x(focused.at)))
                .foregroundStyle(Palette.secondaryInk.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .accessibilityHidden(true)
            ringedDot(at: focused, on: scale)
        }
    }

    /// A filled dot with a ring in the page color, so it stays legible where it crosses the line.
    @ChartContentBuilder
    private func ringedDot(at point: EquityCurvePoint, on scale: EquityChartScale) -> some ChartContent {
        PointMark(x: .value("Time", scale.x(point.at)), y: .value("Equity", point.value))
            .symbolSize(120)
            .foregroundStyle(Palette.page)
            .accessibilityHidden(true)
        PointMark(x: .value("Time", scale.x(point.at)), y: .value("Equity", point.value))
            .symbolSize(50)
            .foregroundStyle(tone(point.value))
            .accessibilityHidden(true)
    }

    /// A day fills the width from its first point to a little past the latest, never less than an
    /// hour, so a morning's line is not squeezed into a corner of an empty afternoon. Longer ranges
    /// keep their whole span.
    private func xDomain(on scale: EquityChartScale) -> ClosedRange<Double> {
        guard scale.isDay else { return 0...1 }
        let start = scale.x(stats.open.at)
        let end = scale.x(max(stats.last.at, stats.open.at.addingTimeInterval(3_600)))
        return start...max(end, start + 0.05)
    }
}
