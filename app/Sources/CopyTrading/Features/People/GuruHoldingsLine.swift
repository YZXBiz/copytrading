import DesktopCore
import SwiftUI

/// What the owner holds from one guru's calls right now, as one sentence under the guru's numbers:
/// "Holding $1,234 in 4 stocks from these calls", then how that stands today, up or down with its
/// own arrow. Nothing shows while nothing from this guru is held in a set-up account.
struct GuruHoldingsLine: View {
    let holdings: GuruHoldings?

    var body: some View {
        if let holdings {
            let cost = holdings.cost
            let gain = holdings.gain
            let stocks = holdings.stocks
            let direction = ChangeDirection(gain)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(
                    L10n.string(
                        stocks == 1 ? "Holding %@ in 1 stock from these calls" : "Holding %@ in %lld stocks from these calls",
                        cost.formatted(.currency(code: "USD").precision(.fractionLength(0))), Int64(stocks))
                )
                .foregroundStyle(Palette.secondaryInk)
                if cost > 0 {
                    Label {
                        Text(
                            "\(gain.magnitude.formatted(.currency(code: "USD"))) (\((gain / cost * 100).magnitude.formatted(.number.precision(.fractionLength(1))))%)"
                        )
                    } icon: {
                        Image(systemName: direction.symbol)
                    }
                    .foregroundStyle(direction.color)
                    .monospacedDigit()
                }
            }
            .font(DesignTokens.lede)
            .tracking(DesignTokens.ledeTracking)
            .accessibilityElement(children: .combine)
        }
    }
}
