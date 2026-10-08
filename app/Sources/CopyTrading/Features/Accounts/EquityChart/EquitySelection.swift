import Foundation

/// What the reader is inspecting on the chart: nothing, one point, or the move between two points.
enum EquitySelection: Equatable {
    case none
    /// The time under the pointer or the keyboard cursor.
    case point(Date)
    /// A dragged span; `settled` once the drag ends, so it stays until clicked away.
    case span(Date, Date, settled: Bool)

    var point: Date? {
        if case .point(let date) = self { return date }
        return nil
    }

    var span: (start: Date, end: Date)? {
        if case .span(let first, let second, _) = self { return (min(first, second), max(first, second)) }
        return nil
    }

    var isSettledSpan: Bool {
        if case .span(_, _, settled: true) = self { return true }
        return false
    }
}
