import DesktopCore
import SwiftUI

/// One feed row: what happened as a sentence, who made it happen and when beneath, and the
/// dollars that moved on the right.
struct AccountFeedRow: View {
    let item: AccountFeedItem
    let directory: GuruDirectory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.tone.symbol)
                .foregroundStyle(item.tone.color)
                .font(.caption)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.sentence)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Text(L10n.string("%@ · %@", item.origin(directory), item.time))
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            if item.isTrade, let amount = Decimal(engine: item.amount) {
                MoneyText(value: amount, font: .callout)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}
