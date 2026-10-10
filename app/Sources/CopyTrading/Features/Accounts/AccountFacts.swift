import DesktopCore
import SwiftUI

/// The account in four figures under its curve, on one grid so every label and number lines up:
/// cash and buying power, then today's loss and what is in stocks, each against its limit with a
/// thin meter. One quiet line under them holds the per-order and per-stock caps, the one way to
/// change limits, and when the numbers were read. Nothing else on the page edits limits.
struct AccountFacts: View {
    let account: AccountOverview
    let policy: TradingAccountPolicy?
    let model: AppModel
    let feature: AccountFeatureModel
    let editLimits: () -> Void

    /// Nil until the account's balance has been read, so an unread account never shows as empty.
    private var lossToday: Decimal? {
        guard let balance = account.balance else { return nil }
        guard let change = Decimal(engine: balance.dayChangeUSD), change < 0 else { return 0 }
        return -change
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 44, verticalSpacing: 22) {
                    GridRow {
                        balance
                        limits
                    }
                }
                Grid(alignment: .topLeading, horizontalSpacing: 44, verticalSpacing: 22) {
                    GridRow { balance }
                    GridRow { limits }
                }
            }
            footer
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var balance: some View {
        figure("Cash", account.balance?.cash)
        figure("Buying power", account.balance?.buyingPower)
    }

    @ViewBuilder
    private var limits: some View {
        if let policy {
            if let cap = Decimal(engine: policy.dailyLossCapUSD) {
                LimitMeter(title: "Loss today", used: lossToday, limit: cap)
                    .frame(width: 200, alignment: .leading)
            }
            if let cap = Decimal(engine: policy.maxTotalUSD) {
                LimitMeter(
                    title: "In stocks", used: account.balance == nil ? nil : Decimal(engine: account.totalExposureUSD) ?? 0,
                    limit: cap,
                    note: ExposureSplit.note(account)
                )
                .frame(width: 200, alignment: .leading)
            }
        }
    }

    private func figure(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(L10n.string(title))
            if let amount = Decimal(engine: value) {
                MoneyText(value: amount, font: DesignTokens.statValue)
                    .foregroundStyle(Palette.ink)
            } else {
                // Not read yet: a dash, never a $0 that reads as an empty account.
                Text("—")
                    .font(DesignTokens.statValue)
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            if let policy {
                Text(caps(policy))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
                Button(L10n.string("Edit Limits"), action: editLimits)
                    .buttonStyle(QuietTextButtonStyle())
                    .accessibilityIdentifier("account.editLimits")
            }
            Spacer(minLength: 12)
            if let balance = account.balance {
                AccountFreshness(
                    observedAt: balance.observedAt,
                    isRefreshing: feature.isRefreshing,
                    engineStopped: model.runtimeState == .stopped || model.runtimeState == .failed,
                    refresh: { Task { await feature.refresh(using: model.accountActions()) } },
                    compact: true
                )
                .font(DesignTokens.caption)
            }
        }
    }

    /// "Max $500 an order · $600 a stock".
    private func caps(_ policy: TradingAccountPolicy) -> String {
        let money = Decimal.FormatStyle.Currency(code: "USD").precision(.fractionLength(0))
        let order = Decimal(engine: policy.maxOrderUSD)?.formatted(money) ?? policy.maxOrderUSD
        let stock = Decimal(engine: policy.maxSymbolUSD)?.formatted(money) ?? policy.maxSymbolUSD
        return L10n.string("Max %@ an order · %@ a stock", order, stock)
    }
}
