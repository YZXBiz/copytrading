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
    /// The plot's size, so time marks are as fine as the room allows and session names get a
    /// strip of their own.
    @State private var plotWidth: Double = 800
    @State private var plotHeight: Double = 176
    /// The strip at the top of a day kept clear of the line for the session names.
    private static let sessionNameStrip: Double = 28

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

    /// The values the plot spans: a day adds a strip on top that the line never climbs into, for
    /// the session names; the value axis marks only `valueRange`, so no mark sits in the strip.
    private var plotRange: ClosedRange<Double> {
        let (lower, upper) = valueRange
        guard scale.isDay, plotHeight > Self.sessionNameStrip * 2 else { return lower...upper }
        return lower...(upper + (upper - lower) * Self.sessionNameStrip / (plotHeight - Self.sessionNameStrip))
    }

    /// The value the axis tag shows: the point being read, else the latest.
    private var tagged: EquityCurvePoint { focused ?? measure?.end ?? stats.last }

    var body: some View {
        let bounds = valueRange
        let axis = EquityValueAxis(lower: bounds.lower, upper: bounds.upper, count: 3)
        let scale = self.scale
        let times = scale.ticks(in: AppTime.zone, locale: AppTime.locale, width: plotWidth)
        let domain = xDomain(on: scale)
        let runs = EquityLineRun.runs(curve.points, on: scale)
        Chart {
            sessionBands(scale.extendedSessions, in: domain)
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
        .chartYScale(domain: plotRange)
        .chartXAxis {
            AxisMarks(values: times.map(\.x).filter { domain.contains($0) }) { value in
                AxisTick(centered: true, length: 4, stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Palette.tertiaryInk.opacity(0.6))
                AxisValueLabel(collisionResolution: .greedy) {
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
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            plotWidth = $0.width - valueAxisWidth
            plotHeight = $0.height - 24
        }
    }

    /// Pre-market and after hours as faint bands behind the line, each named in a strip at its top
    /// that the line stays below, so the names never share the time axis's row or cross the line.
    /// A band too narrow for its name stays unnamed rather than spilling past its edges.
    @ChartContentBuilder
    private func sessionBands(_ sessions: [EquityChartScale.Session], in domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(sessions.filter { $0.end > domain.lowerBound && $0.start < domain.upperBound }, id: \.self) { session in
            let from = max(session.start, domain.lowerBound)
            let to = min(session.end, domain.upperBound)
            RectangleMark(xStart: .value("From", from), xEnd: .value("To", to))
                .foregroundStyle(Palette.ink.opacity(0.035))
                .annotation(position: .overlay, alignment: .top, spacing: 5) {
                    // One line, else a word to a line, else no name.
                    ViewThatFits(in: .horizontal) {
                        sessionName(session.name).fixedSize()
                        sessionName(session.name.replacingOccurrences(of: " ", with: "\n").replacingOccurrences(of: "-", with: "-\n"))
                            .fixedSize()
                            .multilineTextAlignment(.center)
                        Color.clear.frame(width: 0, height: 0)
                    }
                    .frame(width: max(plotWidth * (to - from) / (domain.upperBound - domain.lowerBound) - 4, 0))
                }
                .accessibilityLabel(session.name)
        }
    }

    private func sessionName(_ name: String) -> some View {
        Text(name.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.tertiaryInk.opacity(0.8))
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
