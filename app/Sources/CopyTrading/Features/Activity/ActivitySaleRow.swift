import DesktopCore
import SwiftUI

/// A sale the owner made, among the posts: "You" where a post names its guru, then what sold.
struct ActivitySaleRow: View {
    let accountID: String
    let item: AccountFeedItem
    var showsAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(L10n.string("You"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: 4)
                Text(item.time)
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
                    .fixedSize()
            }
            Text(item.sentence)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Label(L10n.string("Sold by you"), systemImage: item.tone.symbol)
                    .foregroundStyle(item.tone.color)
                if showsAccount {
                    Text(accountID)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }
            }
            .font(.caption)
        }
        .accessibilityElement(children: .combine)
    }
}
