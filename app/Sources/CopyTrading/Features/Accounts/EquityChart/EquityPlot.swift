import Charts
import DesktopCore
import SwiftUI

/// The combined curve, drawn on the app's chart paper: one smooth line in the day's color over a
/// soft wash, with the marks for a point or span the pointer reads drawn over it. The line never
/// reads the pointer, so a hover redraws only those marks. A day always spans its whole session,
/// as Stocks and most brokers draw it: the line stops at the latest balance and the rest of the
/// day stays blank, so regular hours keep most of the width and the time marks stay put.
struct EquityPlot: View {
    let curve: EquityCurve
    let stats: EquityCurveStats
    let range: EquityHistoryRange
    let pointer: EquityPointer
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption) private var valueAxisWidth = 84
    /// The plot's size, so time marks are as fine as the room allows and session names get a
    /// strip of their own.
    @State private var plotWidth: Double = 800
    @State private var plotHeight: Double = 176
    /// The strip at the top of a day kept clear of the line for the session names.
    private static let sessionNameStrip: Double = 28
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

    /// The values the plot spans: a day adds a strip on top that the line never climbs into, for
    /// the session names; the value axis marks only `valueRange`, so no mark sits in the strip.
    private var plotRange: ClosedRange<Double> {
        let (lower, upper) = valueRange
        guard scale.isDay, plotHeight > Self.sessionNameStrip * 2 else { return lower...upper }
        return lower...(upper + (upper - lower) * Self.sessionNameStrip / (plotHeight - Self.sessionNameStrip))
    }

    var body: some View {
        let bounds = valueRange
        let axis = EquityValueAxis(lower: bounds.lower, upper: bounds.upper, count: 3)
        let scale = self.scale
        let times = scale.ticks(in: AppTime.zone, locale: AppTime.locale, width: plotWidth)
        let runs = EquityLineRun.runs(curve.points, on: scale)
        Chart {
            sessionBands(scale.extendedSessions)
            referenceLine
            // One vectorized plot for the whole line, a series per run, so the chart lays it out
            // once instead of a mark per point.
            LinePlot(
                runs.flatMap(\.plotted), x: .value("Time", \.x), y: .value("Equity", \.value),
                series: .value("Run", \.run)
            )
            .foregroundStyle(by: .value("Session", \.session))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: contrast == .increased ? 2.25 : 1.75, lineCap: .round, lineJoin: .round))
            PointMark(x: .value("Time", scale.x(stats.last.at)), y: .value("Equity", stats.last.value))
                .symbolSize(30)
                .foregroundStyle(Palette.ink)
                .accessibilityHidden(true)
        }
        .chartXScale(domain: 0...1, range: .plotDimension(startPadding: 4, endPadding: 14))
        .chartYScale(domain: plotRange)
        .chartForegroundStyleScale(
            domain: [EquityLineRun.regularSession, EquityLineRun.extendedSession],
            range: [Palette.ink, Palette.ink.opacity(0.35)]
        )
        .chartLegend(.hidden)
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
                    namesStrip: scale.isDay ? Self.sessionNameStrip : 0,
                    axisTicks: axis.ticks, axisWidth: valueAxisWidth, axisSpacing: Self.axisSpacing)
                EquityPointerLayer(proxy: proxy, scale: scale, pointer: pointer, measures: true)
            }
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
    private func sessionBands(_ sessions: [EquityChartScale.Session]) -> some ChartContent {
        ForEach(sessions, id: \.self) { session in
            RectangleMark(xStart: .value("From", session.start), xEnd: .value("To", session.end))
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
                    .frame(width: max(plotWidth * (session.end - session.start) - 4, 0))
                }
                .accessibilityLabel(session.name)
        }
    }

    private func sessionName(_ name: String) -> some View {
        Text(name.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.tertiaryInk)
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
