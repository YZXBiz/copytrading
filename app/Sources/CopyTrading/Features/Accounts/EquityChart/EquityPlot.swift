import Charts
import DesktopCore
import SwiftUI

/// The combined curve, drawn on the app's chart paper: one smooth line in the day's color over a
/// soft wash, with the marks for a point or span the pointer reads drawn over it. The line never
/// reads the pointer, so a hover redraws only those marks. A day always spans its whole New York
/// day, midnight to midnight: the line stops at the latest balance and the rest of the day stays
/// blank, so the time marks stay put.
struct EquityPlot: View {
    /// A point where the plot draws it: its position across the plot and its value.
    struct Plotted {
        let x: Double
        let value: Double
    }

    let curve: EquityCurve
    let stats: EquityCurveStats
    let range: EquityHistoryRange
    let pointer: EquityPointer
    /// Waiting calls, each a thin amber rule at the time it was posted.
    var callMarks: [EquityCallMark] = []
    /// The call whose ticket or marker is under the pointer: its rule turns solid.
    var highlightedCall: Binding<String?> = .constant(nil)
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption) private var valueAxisWidth = 84
    /// The plot's width, so time marks are as fine as the room allows.
    @State private var plotWidth: Double = 800
    /// The lit call came from the pointer on its marker, not from its ticket.
    @State private var litByMarker = false
    /// The gap between the plot and the value axis's labels.
    private static let axisSpacing: CGFloat = 6

    private var reference: Double { stats.reference }
    private var scale: EquityChartScale { EquityChartScale(range: range, first: stats.open.at, last: stats.last.at) }
    private var valueRange: (lower: Double, upper: Double) {
        let low = min(stats.low.value, reference)
        let high = max(stats.high.value, reference)
        let margin = max((high - low) * 0.16, 1)
        return (low - margin, high + margin)
    }

    /// The calls inside the shown range; one from before the range's first point is left off
    /// rather than pinned to the edge.
    private var shownCalls: [EquityCallMark] {
        callMarks.filter { $0.at >= stats.open.at && $0.at <= stats.last.at }
    }

    /// The top of the plot: above the line's values by a strip for the calls' diamonds and times,
    /// so they never sit on the line or get cut off. The value axis marks only `valueRange`.
    private var plotTop: Double {
        let (lower, upper) = valueRange
        return shownCalls.isEmpty ? upper : upper + (upper - lower) * 0.14
    }

    var body: some View {
        let bounds = valueRange
        let axis = EquityValueAxis(lower: bounds.lower, upper: bounds.upper, count: 3)
        let scale = self.scale
        let times = scale.ticks(in: AppTime.zone, locale: AppTime.locale, width: plotWidth)
        Chart {
            referenceLine
            callRules(scale)
            // One vectorized plot for the whole line, so the chart lays it out once instead of a
            // mark per point.
            LinePlot(
                curve.points.map { Plotted(x: scale.x($0.at), value: $0.value) }, x: .value("Time", \.x),
                y: .value("Equity", \.value)
            )
            .foregroundStyle(Palette.ink)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: contrast == .increased ? 2.25 : 1.75, lineCap: .round, lineJoin: .round))
            // Its x is a share of the day, which VoiceOver would read as "0.1 to 0.2". The chart's
            // summary and the arrow keys' readout say the line in money and times instead.
            .accessibilityHidden(true)
            PointMark(x: .value("Time", scale.x(stats.last.at)), y: .value("Equity", stats.last.value))
                .symbolSize(30)
                .foregroundStyle(Palette.ink)
                .accessibilityHidden(true)
        }
        .chartXScale(domain: 0...1, range: .plotDimension(startPadding: 4, endPadding: 14))
        .chartYScale(domain: bounds.lower...plotTop)
        .chartXAxis {
            AxisMarks(values: times.map(\.x)) { value in
                AxisTick(centered: true, length: 4, stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Palette.tertiaryInk.opacity(0.6))
                AxisValueLabel(anchor: .top, collisionResolution: .greedy) {
                    if let x = value.as(Double.self), let tick = times.first(where: { abs($0.x - x) < 1e-9 }) {
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
                AxisValueLabel(horizontalSpacing: Self.axisSpacing) {
                    if let amount = value.as(Double.self) {
                        Text(axis.money(amount))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(minWidth: valueAxisWidth, alignment: .leading)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            ZStack {
                EquitySelectionMarks(
                    proxy: proxy, scale: scale, curve: curve, reference: reference, pointer: pointer,
                    axisTicks: axis.ticks, axisWidth: valueAxisWidth, axisSpacing: Self.axisSpacing)
                EquityPointerLayer(proxy: proxy, scale: scale, pointer: pointer, measures: true)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            plotWidth = $0 - valueAxisWidth
        }
        .onChange(of: pointer.selection) { _, selection in
            // Reading the curve at a call's marker lights its ticket, and moving off lets go.
            let near = selection.point.flatMap { point in
                callMarks.first { abs(scale.x($0.at) - scale.x(point)) < 0.012 }
            }
            if let near {
                highlightedCall.wrappedValue = near.id
                litByMarker = true
            } else if litByMarker {
                highlightedCall.wrappedValue = nil
                litByMarker = false
            }
        }
    }

    /// Each waiting call that falls inside the shown range: an amber rule at the time it was posted,
    /// with a small diamond and its time in the strip at the top of the plot.
    @ChartContentBuilder
    private func callRules(_ scale: EquityChartScale) -> some ChartContent {
        // The middle of the strip, so the diamond and its time sit wholly inside the plot.
        let top = (valueRange.upper + plotTop) / 2
        ForEach(shownCalls) { mark in
            let isLit = highlightedCall.wrappedValue == mark.id
            RuleMark(x: .value("Call", scale.x(mark.at)))
                .foregroundStyle(Palette.amber.opacity(isLit ? 1 : 0.7))
                .lineStyle(StrokeStyle(lineWidth: isLit ? 1.5 : 1.2, dash: isLit ? [] : [1, 3]))
                .accessibilityLabel(mark.label)
            PointMark(x: .value("Call", scale.x(mark.at)), y: .value("Equity", top))
                .symbol(.diamond)
                .symbolSize(isLit ? 56 : 40)
                .foregroundStyle(Palette.amber)
                .annotation(position: .trailing, alignment: .center, spacing: 4) {
                    Text(mark.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                        .fixedSize()
                }
                .accessibilityHidden(true)
        }
    }

    @ChartContentBuilder
    private var referenceLine: some ChartContent {
        RuleMark(y: .value(curve.baseline == nil ? "Start" : "Previous close", reference))
            .foregroundStyle(contrast == .increased ? Palette.secondaryInk : Palette.tertiaryInk.opacity(0.75))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            .accessibilityLabel(L10n.string(curve.baseline == nil ? "Start" : "Previous close"))
            .accessibilityValue(reference.formatted(.currency(code: "USD")))
    }
}
