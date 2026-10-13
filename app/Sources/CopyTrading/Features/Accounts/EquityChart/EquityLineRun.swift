import DesktopCore

/// A stretch of a curve inside one kind of session: full strength in regular hours, quieter in
/// pre-market and after hours. Adjacent runs share their boundary point, so the line stays whole.
struct EquityLineRun: Identifiable {
    /// A point where the plot draws it: its run, the run's session, its position across the plot,
    /// and its value.
    struct Plotted {
        let run: Int
        let session: String
        let x: Double
        let value: Double
    }

    let id: Int
    let points: [EquityCurvePoint]
    let isExtended: Bool
    let plotted: [Plotted]

    static let regularSession = "regular"
    static let extendedSession = "extended"

    static func runs(_ points: [EquityCurvePoint], on scale: EquityChartScale) -> [EquityLineRun] {
        guard let first = points.first else { return [] }
        var runs: [EquityLineRun] = []
        var current = [first]
        var extended = scale.isExtended(first.at)
        func close() {
            let session = extended ? Self.extendedSession : Self.regularSession
            let plotted = current.map { Plotted(run: runs.count, session: session, x: scale.x($0.at), value: $0.value) }
            runs.append(EquityLineRun(id: runs.count, points: current, isExtended: extended, plotted: plotted))
        }
        for point in points.dropFirst() {
            current.append(point)
            let pointExtended = scale.isExtended(point.at)
            if pointExtended != extended {
                close()
                current = [point]
                extended = pointExtended
            }
        }
        close()
        return runs
    }
}
