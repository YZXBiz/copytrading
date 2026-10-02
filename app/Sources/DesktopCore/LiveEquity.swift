import Foundation

/// Brings a broker equity curve up to the moment the account balance was read.
///
/// The broker records equity in five-minute bars, so the newest bar trails the live balance by up
/// to five minutes. Shown side by side, "Balance $9,438.26" and a chart ending at $9,447.76 name two
/// values for one quantity. The curve therefore ends at the balance, stamped with the time it was read.
public enum LiveEquity {
    public typealias AccountHistory = (accountID: String, history: EquityHistory)

    /// Each history with the balance of its account appended as its last point. Every account gets
    /// the same timestamp, the latest balance read, so the combined curve still adds them up.
    public static func extend(_ histories: [AccountHistory], balances: [String: AccountBalance]) -> [AccountHistory] {
        let readings = histories.compactMap { entry in
            balances[entry.accountID].flatMap { balance in
                EquityCurve.date(balance.observedAt).map { (at: $0, text: balance.observedAt) }
            }
        }
        guard let latest = readings.max(by: { $0.at < $1.at }) else { return histories }
        return histories.map { entry in
            guard let balance = balances[entry.accountID] else { return entry }
            return (entry.accountID, entry.history.reaching(balance, at: latest.at, stamp: latest.text))
        }
    }
}

extension EquityHistory {
    /// This history with `balance` appended as its last point, when that point belongs on it:
    /// the window ends now (not a chosen past day), the balance is newer than the last bar, is
    /// funded, and for a day falls inside the same extended trading day as the bar before it.
    fileprivate func reaching(_ balance: AccountBalance, at time: Date, stamp: String) -> EquityHistory {
        guard window.day == nil,
            let equity = EquityCurve.amount(balance.equity), equity > 0,
            let lastText = points.last?.at, let last = EquityCurve.date(lastText),
            time > last
        else { return self }
        if window.range == .day, !MarketSession.tradingDay(containing: last).contains(time) { return self }
        return EquityHistory(
            window: window, baseValue: baseValue,
            points: points + [EquityPoint(at: stamp, equity: balance.equity)]
        )
    }
}
