import DesktopCore
import SwiftUI

/// What the owner holds from one guru's calls right now, as one sentence under the guru's numbers:
/// "Holding $1,234 in 4 stocks from these calls", then how that stands today, up or down with its
/// own arrow. Nothing shows while nothing from this guru is held.
struct GuruHoldingsLine: View {
    let guruID: String
    let accounts: [AccountOverview]

    private var lots: [(lot: AccountLotView, symbol: String)] {
        accounts.flatMap { account in
            account.positions.flatMap { position in
                position.lots.filter { $0.guruID == guruID && (Decimal(engine: $0.remainingQty) ?? 0) > 0 }
                    .map { ($0, position.symbol) }
            }
        }
    }

    var body: some View {
        let lots = self.lots
        if !lots.isEmpty {
            let cost = lots.reduce(Decimal(0)) {
                $0 + (Decimal(engine: $1.lot.remainingQty) ?? 0) * (Decimal(engine: $1.lot.averagePrice) ?? 0)
            }
            let gain = lots.compactMap { Decimal(engine: $0.lot.unrealizedPL) }.reduce(0, +)
            let stocks = Set(lots.map(\.symbol)).count
            let direction = ChangeDirection(gain)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(
                    L10n.string(
                        "Holding %@ in %@ from these calls",
                        cost.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                        Humanize.count(stocks, "stock"))
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
