import DesktopCore
import SwiftUI

/// Current broker evidence stays separate from the historical window being read in the chart.
struct TodaySummary: View {
    let balances: [AccountBalance]
    let accountCount: Int

    private var change: Decimal { balances.compactMap { Decimal(engine: $0.dayChangeUSD) }.reduce(0, +) }
    private var equity: Decimal { balances.compactMap { Decimal(engine: $0.equity) }.reduce(0, +) }
    private var previousClose: Decimal { balances.compactMap { Decimal(engine: $0.previousCloseEquity) }.reduce(0, +) }
    private var oldest: Date? { balances.compactMap { Humanize.date($0.observedAt) }.min() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if balances.isEmpty {
                Text(
                    L10n.string(
                        accountCount == 0
                            ? "Your broker's numbers appear once an account is read."
                            : "Start copying to read today's balance from your broker."
                    )
                )
                .font(DesignTokens.caption)
                .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        balance
                        dailyChange
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        balance
                        dailyChange
                    }
                }
                asOf
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var balance: some View {
        HStack(spacing: 6) {
            Text(L10n.string("Latest broker balance"))
                .font(DesignTokens.caption)
                .foregroundStyle(.secondary)
            MoneyText(value: equity, font: DesignTokens.bodyEmphasis)
        }
    }

    private var dailyChange: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(L10n.string("Today"))
                .font(DesignTokens.caption)
                .foregroundStyle(.secondary)
            MoneyText(value: change, style: .change, font: DesignTokens.bodyEmphasis)
                .accessibilityIdentifier("today.change")
            if previousClose > 0 {
                Text(
                    (change / previousClose).doubleValue,
                    format: .percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false))
                )
                .font(DesignTokens.caption)
                .monospacedDigit()
                .foregroundStyle(ChangeDirection(change).color)
            }
        }
    }

    @ViewBuilder
    private var asOf: some View {
        if let oldest {
            Text(
                L10n.string(
                    "%@ · as of %@",
                    Humanize.count(balances.count, "account"),
                    oldest.formatted(AppTime.style(.dateTime.hour().minute()))
                )
            )
            .font(DesignTokens.caption)
            .foregroundStyle(.secondary)
        }
    }
}
