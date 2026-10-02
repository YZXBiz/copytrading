import Charts
import SwiftUI

/// Hover scrubs a point, a drag measures a span, and a click clears a settled span.
struct EquityPointerLayer: View {
    let proxy: ChartProxy
    /// Positions on the plot are fractions of the session; the scale turns them back into times.
    let scale: EquityChartScale
    @Binding var selection: EquitySelection
    /// The by-account view reads points only; measuring a span belongs to the total.
    let measures: Bool

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear)
                .contentShape(.rect)
                .onContinuousHover { phase in
                    // A span being dragged or settled keeps the pointer until it is clicked away.
                    if selection.span != nil { return }
                    switch phase {
                    case .active(let location):
                        selection = date(at: location, in: geometry).map(EquitySelection.point) ?? .none
                    case .ended:
                        selection = .none
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard measures, abs(drag.translation.width) > 3,
                                let start = date(at: drag.startLocation, in: geometry),
                                let end = date(at: drag.location, in: geometry)
                            else { return }
                            selection = .span(start, end, settled: false)
                        }
                        .onEnded { drag in
                            if case .span(let start, let end, _) = selection, abs(drag.translation.width) > 3 {
                                selection = .span(start, end, settled: true)
                            } else {
                                selection = date(at: drag.location, in: geometry).map(EquitySelection.point) ?? .none
                            }
                        }
                )
        }
    }

    /// The chart time under `location`, or nil outside the plot.
    private func date(at location: CGPoint, in geometry: GeometryProxy) -> Date? {
        guard let anchor = proxy.plotFrame else { return nil }
        let frame = geometry[anchor]
        guard frame.minX...frame.maxX ~= location.x else { return nil }
        return proxy.value(atX: location.x - frame.minX, as: Double.self).map(scale.date(atX:))
    }
}
