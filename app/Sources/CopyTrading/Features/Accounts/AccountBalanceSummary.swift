import DesktopCore
import SwiftUI

/// What the account is worth, in the display face, with how today went and when it was read under
/// it, and its cash and buying power at the trailing edge. On a narrow page they move under it.
struct AccountBalanceSummary: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel

    var body: some View {
        if let balance = account.balance {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 24) {
                    worth(balance)
                    Spacer(minLength: 0)
                    facts(balance)
                }
                VStack(alignment: .leading, spacing: 14) {
                    worth(balance)
                    facts(balance)
                }
            }
        }
    }

    private func worth(_ balance: AccountBalance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MoneyText(
                value: Decimal(engine: balance.equity) ?? 0, font: DesignTokens.balanceDisplay,
                centsFont: DesignTokens.balanceCents
            )
            .tracking(DesignTokens.balanceTracking)
            .foregroundStyle(Palette.ink)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                change(balance)
                freshness(balance)
            }
            .fixedSize()
        }
    }

    /// Cash and buying power, a label over each amount.
    private func facts(_ balance: AccountBalance) -> some View {
        HStack(alignment: .bottom, spacing: 28) {
            fact("Cash", balance.cash)
            fact("Buying power", balance.buyingPower)
        }
        .fixedSize()
        .padding(.bottom, 4)
    }

    private func fact(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(L10n.string(title))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
            Text(money(value))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    /// Today's change, its percent, and "today": one phrase for VoiceOver.
    private func change(_ balance: AccountBalance) -> some View {
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
        .accessibilityElement(children: .combine)
    }

    private func freshness(_ balance: AccountBalance) -> some View {
        AccountFreshness(
            observedAt: balance.observedAt,
            isRefreshing: feature.isRefreshing,
            engineStopped: model.runtimeState == .stopped || model.runtimeState == .failed,
            refresh: { Task { await feature.refresh(using: model.accountActions()) } }
        )
        .padding(.leading, 14)
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
