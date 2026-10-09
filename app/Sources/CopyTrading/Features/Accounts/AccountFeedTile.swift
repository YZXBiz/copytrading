import DesktopCore
import SwiftUI

/// One thing that happened in the account, as a gallery tile on the white page: the dollars that
/// moved set large, what happened in a sentence, and who did it on the corner chip. A tile that
/// came from a guru's post is marked in butter under the pointer, shows its ↗, and opens the post.
struct AccountFeedTile: View {
    let item: AccountFeedItem
    let directory: GuruDirectory
    let isSelected: Bool
    /// Opens the post the tile came from; nil when the owner did it or the post is gone.
    let open: (() -> Void)?
    /// The top tile of a column sits under the switcher's own line, so it draws none.
    var showsRule = true
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let figure = DisplayFont.font(size: 30, weight: .regular, relativeTo: .title)

    var body: some View {
        if let open {
            Button(action: open) { content }
                .buttonStyle(QuietPressButtonStyle())
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isHovered)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsRule {
                Hairline()
                    .padding(.bottom, 8)
            }
            HStack(alignment: .top, spacing: 12) {
                if item.isTrade, let amount = Decimal(engine: item.amount) {
                    Text(amount, format: .currency(code: "USD"))
                        .font(Self.figure)
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .markerHighlight(open != nil && (isHovered || isSelected))
                }
                Spacer(minLength: 0)
                if open != nil {
                    OpenArrow(isShown: isHovered || isSelected)
                }
            }
            Text(item.sentence)
                .font(DesignTokens.bodyText)
                .foregroundStyle(item.isTrade ? Palette.secondaryInk : Palette.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            CreditChip(name: item.credit(directory), time: item.time)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
