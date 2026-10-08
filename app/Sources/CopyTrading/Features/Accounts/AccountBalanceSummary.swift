import DesktopCore
import SwiftUI

/// The broker's numbers for the account: what it is worth, how today went, the cash, stocks and
/// buying power behind it, and when the prices were read.
struct AccountBalanceSummary: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel

    var body: some View {
        if let balance = account.balance {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    MoneyText(value: Decimal(engine: balance.equity) ?? 0, font: DesignTokens.balanceDisplay)
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
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .lastTextBaseline, spacing: 24) {
                        stats
                        Spacer(minLength: 16)
                        freshness(balance)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 24) { stats }
                        freshness(balance)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        if let balance = account.balance {
            stat("Cash", balance.cash)
            stat("In stocks", account.totalExposureUSD)
            stat("Buying power", balance.buyingPower)
        }
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string(title))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
            MoneyText(value: Decimal(engine: value) ?? 0, font: DesignTokens.statValue)
                .foregroundStyle(Palette.ink)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private func freshness(_ balance: AccountBalance) -> some View {
        AccountFreshness(
            observedAt: balance.observedAt,
            isRefreshing: feature.isRefreshing,
            engineStopped: model.runtimeState == .stopped || model.runtimeState == .failed,
            refresh: { Task { await feature.refresh(using: model.accountActions()) } }
        )
    }

    /// Today's change against yesterday's close, the equity less the change.
    private func dayChangeFraction(_ balance: AccountBalance) -> Double? {
        guard let equity = Decimal(engine: balance.equity), let change = Decimal(engine: balance.dayChangeUSD) else { return nil }
        let previous = equity - change
        guard previous > 0 else { return nil }
        return (change / previous).doubleValue
    }
}
