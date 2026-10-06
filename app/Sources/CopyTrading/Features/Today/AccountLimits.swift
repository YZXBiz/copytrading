import DesktopCore
import SwiftUI

/// One account's daily loss and exposure against its own policy.
struct AccountLimits: View {
    let configuration: TradingAccountConfiguration
    let overview: AccountOverview?

    private var lossToday: Decimal {
        guard let change = Decimal(engine: overview?.balance?.dayChangeUSD), change < 0 else { return 0 }
        return -change
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    accountIdentity
                    Spacer(minLength: 4)
                    entries
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) {
                    accountIdentity
                    entries
                }
            }
            if let dailyCap = Decimal(engine: configuration.policy.dailyLossCapUSD) {
                LimitMeter(title: "Loss today", used: lossToday, limit: dailyCap)
            }
            if let totalCap = Decimal(engine: configuration.policy.maxTotalUSD) {
                LimitMeter(
                    title: "In stocks",
                    used: Decimal(engine: overview?.totalExposureUSD) ?? 0,
                    limit: totalCap
                )
            }
        }
    }

    private var accountIdentity: some View {
        HStack(spacing: 8) {
            Text(configuration.id)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(configuration.id)
                .help(configuration.id)
                .fixedSize(horizontal: false, vertical: true)
            EnvironmentBadge(environment: configuration.environment)
        }
    }

    private var entries: some View {
        Text(entriesText)
            .font(.callout)
            .foregroundStyle(entriesTone.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @MainActor private var entriesText: String {
        L10n.string(overview.map { AccountEntryState($0).text } ?? "Not read yet")
    }

    private var entriesTone: StatusTone {
        overview.map { AccountEntryState($0).tone } ?? .inactive
    }
}
