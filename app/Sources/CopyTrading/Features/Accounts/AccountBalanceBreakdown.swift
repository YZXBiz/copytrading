import DesktopCore
import SwiftUI

/// What the balance is made of, in one row under the curve: cash, stocks, and buying power over
/// tracked capitals, with when the prices were read at the trailing edge.
struct AccountBalanceBreakdown: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel

    var body: some View {
        if let balance = account.balance {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 40) {
                    stats(balance)
                    Spacer(minLength: 16)
                    freshness(balance)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 40) { stats(balance) }
                    freshness(balance)
                }
            }
        }
    }

    @ViewBuilder
    private func stats(_ balance: AccountBalance) -> some View {
        stat("Cash", balance.cash)
        stat("In stocks", account.totalExposureUSD)
        stat("Buying power", balance.buyingPower)
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(title).uppercased())
                .font(DesignTokens.eyebrow)
                .tracking(DesignTokens.eyebrowTracking)
                .foregroundStyle(Palette.tertiaryInk)
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
}
