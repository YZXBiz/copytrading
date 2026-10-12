import DesktopCore
import SwiftUI

/// What the account is worth, in the display face, and under it how today went, its cash and buying
/// power, and when it was read.
struct AccountBalanceSummary: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel

    var body: some View {
        if let balance = account.balance {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    MoneyText(value: Decimal(engine: balance.equity) ?? 0, font: DesignTokens.balanceDisplay)
                        .tracking(DesignTokens.balanceTracking)
                        .foregroundStyle(Palette.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        MoneyText(
                            value: Decimal(engine: balance.dayChangeUSD) ?? 0, style: .change,
                            font: DesignTokens.bodyText.weight(.semibold))
                        if let percent = dayChangeFraction(balance) {
                            Text(percent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false))))
                                .font(DesignTokens.bodyText)
                                .monospacedDigit()
                                .foregroundStyle(ChangeDirection(Decimal(engine: balance.dayChangeUSD) ?? 0).color)
                        }
                        Text(L10n.string("today"))
                            .font(DesignTokens.bodyText)
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(
                            L10n.string(
                                "·  %@ cash  ·  %@ buying power", money(balance.cash), money(balance.buyingPower))
                        )
                        .font(DesignTokens.bodyText)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryInk)
                        AccountFreshness(
                            observedAt: balance.observedAt,
                            isRefreshing: feature.isRefreshing,
                            engineStopped: model.runtimeState == .stopped || model.runtimeState == .failed,
                            refresh: { Task { await feature.refresh(using: model.accountActions()) } }
                        )
                        .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func money(_ value: String?) -> String {
        (Decimal(engine: value) ?? 0).formatted(.currency(code: "USD"))
    }

    /// Today's change against yesterday's close, the equity less the change.
    private func dayChangeFraction(_ balance: AccountBalance) -> Double? {
        guard let equity = Decimal(engine: balance.equity), let change = Decimal(engine: balance.dayChangeUSD) else { return nil }
        let previous = equity - change
        guard previous > 0 else { return nil }
        return (change / previous).doubleValue
    }
}
