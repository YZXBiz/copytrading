import DesktopCore
import SwiftUI

/// How close the account is to its own limits, and what those limits are.
struct AccountLimitsPanel: View {
    let account: AccountOverview
    let policy: TradingAccountPolicy

    private var lossToday: Decimal {
        guard let change = Decimal(engine: account.balance?.dayChangeUSD), change < 0 else { return 0 }
        return -change
    }

    var body: some View {
        PageSection("Limits", symbol: "gauge.with.dots.needle.33percent") {
            VStack(alignment: .leading, spacing: 16) {
                if let dailyCap = Decimal(engine: policy.dailyLossCapUSD) {
                    LimitMeter(title: "Loss today", used: lossToday, limit: dailyCap)
                }
                if let totalCap = Decimal(engine: policy.maxTotalUSD) {
                    LimitMeter(title: "Exposure", used: Decimal(engine: account.totalExposureUSD) ?? 0, limit: totalCap)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    rule("Per order", dollars(policy.maxOrderUSD))
                    rule("Per symbol", dollars(policy.maxSymbolUSD))
                    rule("Entries a day", "\(policy.maxEntriesPerDay)")
                    rule("Exits", L10n.string(policy.copyExits ? "Copied" : "Not copied"))
                }
                .font(.callout)
            }
        }
    }

    private func rule(_ title: String, _ value: String) -> some View {
        HStack {
            Text(L10n.string(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private func dollars(_ value: String) -> String {
        Decimal(engine: value)?.formatted(.currency(code: "USD").precision(.fractionLength(0))) ?? value
    }
}
