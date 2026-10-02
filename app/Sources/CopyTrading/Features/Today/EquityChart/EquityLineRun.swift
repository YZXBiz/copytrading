import DesktopCore

/// A stretch of a curve inside one kind of session: full strength in regular hours, quieter in
/// pre-market and after hours. Adjacent runs share their boundary point, so the line stays whole.
struct EquityLineRun: Identifiable {
    let id: Int
    let points: [EquityCurvePoint]
    let isExtended: Bool

    static func runs(_ points: [EquityCurvePoint], on scale: EquityChartScale) -> [EquityLineRun] {
        guard let first = points.first else { return [] }
        var runs: [EquityLineRun] = []
        var current = [first]
        var extended = scale.isExtended(first.at)
        for point in points.dropFirst() {
            current.append(point)
            let pointExtended = scale.isExtended(point.at)
            if pointExtended != extended {
                runs.append(EquityLineRun(id: runs.count, points: current, isExtended: extended))
                current = [point]
                extended = pointExtended
            }
        }
        runs.append(EquityLineRun(id: runs.count, points: current, isExtended: extended))
        return runs
    }
}
