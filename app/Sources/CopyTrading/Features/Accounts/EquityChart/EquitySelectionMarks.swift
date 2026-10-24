import Charts
import DesktopCore
import SwiftUI

/// The marks for what the pointer is reading, drawn over the plot: a rule and a ringed dot at the
/// point under the pointer, or a shaded span with a rule and dot at each end, and the value's tag
/// on the value axis. Only this layer reads the pointer, so a hover leaves the line alone.
struct EquitySelectionMarks: View {
    let proxy: ChartProxy
    let scale: EquityChartScale
    let curve: EquityCurve
    let reference: Double
    let pointer: EquityPointer
    /// The value axis's marks, label width, and gap from the plot, so the tag sits where the labels
    /// do and hides any it would touch.
    let axisTicks: [Double]
    let axisWidth: CGFloat
    let axisSpacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plot = geometry[anchor]
                let marks = plot
                let selection = pointer.selection
                if let span = selection.span, let measure = curve.measure(from: span.start, to: span.end) {
                    let tone = EquityTone.of(change: measure.change)
                    let start = position(of: measure.start, in: plot)
                    let end = position(of: measure.end, in: plot)
                    Rectangle()
                        .fill(tone.opacity(0.08))
                        .frame(width: max(end.x - start.x, 1), height: marks.height)
                        .position(x: (start.x + end.x) / 2, y: marks.midY)
                    rule(at: start.x, in: marks, color: tone.opacity(0.6))
                    rule(at: end.x, in: marks, color: tone.opacity(0.6))
                    ringedDot(at: start, value: measure.start.value)
                    ringedDot(at: end, value: measure.end.value)
                    tag(measure.end.value, at: end.y, in: plot)
                } else if let at = selection.point, let point = curve.nearest(to: at) {
                    let spot = position(of: point, in: plot)
                    rule(at: spot.x, in: marks, color: Palette.secondaryInk.opacity(0.55))
                    ringedDot(at: spot, value: point.value)
                    tag(point.value, at: spot.y, in: plot)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func position(of point: EquityCurvePoint, in plot: CGRect) -> CGPoint {
        CGPoint(
            x: plot.minX + (proxy.position(forX: scale.x(point.at)) ?? 0),
            y: plot.minY + (proxy.position(forY: point.value) ?? 0)
        )
    }

    private func tone(_ value: Double) -> Color {
        value > reference ? EquityTone.of(true) : value < reference ? EquityTone.of(false) : Palette.tertiaryInk
    }

    private func rule(at x: CGFloat, in plot: CGRect, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 1, height: plot.height)
            .position(x: x, y: plot.midY)
    }

    /// A filled dot with a ring in the page color, so it stays legible where it crosses the line.
    private func ringedDot(at spot: CGPoint, value: Double) -> some View {
        Circle()
            .fill(tone(value))
            .padding(2)
            .background(Palette.page, in: .circle)
            .frame(width: 11, height: 11)
            .position(spot)
    }

    /// The value on its gain or loss color where the axis labels sit. An axis label the tag would
    /// touch is hidden whole, never left half covered.
    private func tag(_ value: Double, at y: CGFloat, in plot: CGRect) -> some View {
        let column = plot.maxX + axisSpacing + axisWidth / 2
        let touched = axisTicks.compactMap { proxy.position(forY: $0).map { plot.minY + $0 } }
            .filter { abs($0 - y) < Self.labelClearance }
        return ZStack {
            ForEach(touched, id: \.self) { tickY in
                Rectangle()
                    .fill(Palette.page)
                    .frame(width: axisWidth + 8, height: Self.labelRow)
                    .position(x: column, y: tickY)
            }
            ValueTag(text: value.formatted(.currency(code: "USD")), color: tone(value))
                .frame(minWidth: axisWidth, alignment: .leading)
                .fixedSize()
                .position(x: column, y: y)
        }
    }

    /// The height of an axis label's row, and how near a label may sit to the tag's middle before
    /// the two would touch: half the tag, half a label, and a little air.
    private static let labelRow: CGFloat = 18
    private static let labelClearance: CGFloat = 22
}
