import DesktopCore
import SwiftUI

/// The broker's own numbers for the account, with the time they were read.
struct AccountBalancePanel: View {
    let account: AccountOverview

    var body: some View {
        PageSection("Balance", symbol: "dollarsign.circle") {
            if let balance = account.balance {
                Text(
                    L10n.string(
                        "as of %@",
                        Humanize.date(balance.observedAt)?.formatted(
                            Date.FormatStyle(
                                date: .omitted,
                                time: .shortened,
                                locale: AppTime.locale,
                                timeZone: AppTime.zone
                            )
                        ) ?? "—"
                    )
                )
                .font(DesignTokens.caption)
                .foregroundStyle(.secondary)
            }
        } content: {
            if let balance = account.balance {
                VStack(alignment: .leading, spacing: 6) {
                    MoneyText(value: Decimal(engine: balance.equity) ?? 0, font: DesignTokens.moneyDisplay)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        MoneyText(value: Decimal(engine: balance.dayChangeUSD) ?? 0, style: .change, font: DesignTokens.bodyText)
                        Text(L10n.string("today")).font(DesignTokens.caption).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 14) {
                    StatTile(title: "Cash") {
                        MoneyText(value: Decimal(engine: balance.cash) ?? 0, font: DesignTokens.bodyEmphasis)
                    }
                    StatTile(title: "Buying power") {
                        MoneyText(value: Decimal(engine: balance.buyingPower) ?? 0, font: DesignTokens.bodyEmphasis)
                    }
                    StatTile(title: "In stocks") {
                        MoneyText(value: Decimal(engine: account.totalExposureUSD) ?? 0, font: DesignTokens.bodyEmphasis)
                    }
                }
                .padding(.top, 6)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(L10n.string("The balance appears once copying is on and the broker has been read."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            }
        }
    }
}
