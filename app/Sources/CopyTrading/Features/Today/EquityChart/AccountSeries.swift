import DesktopCore
import SwiftUI

/// One line in the by-account view: an account (or the folded rest), its color, and both curves.
struct AccountSeries: Identifiable {
    let id: String
    let name: String
    let color: Color
    /// Dollars, for the readout.
    let equity: EquityCurve
    /// Change from its own reference as a fraction, the value the lines are drawn on.
    let change: EquityCurve

    /// The first three accounts by current equity keep their own line; the rest fold into "Other accounts".
    static func make(from histories: [(accountID: String, history: EquityHistory)]) -> [AccountSeries] {
        let ranked =
            histories
            .map { (id: $0.accountID, history: $0.history, equity: EquityCurve(combining: [$0.history])) }
            .filter { !$0.equity.points.isEmpty }
            .sorted { ($0.equity.points.last?.value ?? 0) > ($1.equity.points.last?.value ?? 0) }
        let slots = AccountSeriesColor.slots
        let named = ranked.prefix(slots.count)
        var series = named.enumerated().map { index, entry in
            AccountSeries(
                id: entry.id, name: entry.id, color: slots[index],
                equity: entry.equity, change: EquityCurve(changeOf: entry.history)
            )
        }
        let rest = ranked.dropFirst(named.count)
        if !rest.isEmpty {
            let combined = EquityCurve(combining: rest.map(\.history))
            series.append(
                AccountSeries(
                    id: "other", name: "Other accounts", color: AccountSeriesColor.other,
                    equity: combined, change: combined.asChange
                ))
        }
        return series
    }
}

extension EquityCurve {
    /// This curve as a fraction of its own reference.
    fileprivate var asChange: EquityCurve {
        guard let reference, reference != 0 else { return EquityCurve(points: [], baseline: nil) }
        return EquityCurve(
            points: points.map { EquityCurvePoint(at: $0.at, value: ($0.value - reference) / reference) },
            baseline: 0
        )
    }
}
