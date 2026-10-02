import Charts
import DesktopCore
import SwiftUI

/// A small line of today's combined equity for the menu bar panel.
struct MenuBarSparkline: View {
    let accounts: [AccountOverview]
    let histories: [String: EquityHistory]

    private var values: [(Date, Double)] {
        // Today shows another window while the owner browses it; the menu bar is always today.
        let series = accounts.filter(\.activeConfiguration)
            .compactMap { histories[$0.accountID] }
            .filter { $0.window == .today }
        guard !series.isEmpty else { return [] }
        var sums: [Date: (Double, Int)] = [:]
        for history in series {
            for point in history.points {
                guard let at = Humanize.date(point.at), let equity = Decimal(engine: point.equity) else { continue }
                let current = sums[at] ?? (0, 0)
                sums[at] = (current.0 + equity.doubleValue, current.1 + 1)
            }
        }
        return sums.filter { $0.value.1 == series.count }.map { ($0.key, $0.value.0) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        let values = self.values
        // A flat line says nothing, so draw only when the day actually moved.
        if values.count >= 2, let first = values.first?.1, let last = values.last?.1,
            (values.map(\.1).max() ?? 0) - (values.map(\.1).min() ?? 0) >= 0.01
        {
            let tint: Color = last > first ? .green : last < first ? .red : Palette.accent
            let low = values.map(\.1).min() ?? 0
            let high = values.map(\.1).max() ?? 0
            Chart(values, id: \.0) { point in
                AreaMark(x: .value("Time", point.0), yStart: .value("Floor", low), yEnd: .value("Equity", point.1))
                    .foregroundStyle(tint.opacity(0.12))
                LineMark(x: .value("Time", point.0), y: .value("Equity", point.1))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: low...max(high, low + 1))
            .frame(height: 54)
            .accessibilityLabel(L10n.string("Equity today"))
        }
    }
}
