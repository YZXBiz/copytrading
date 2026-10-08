import DesktopCore
import SwiftUI

/// One feed row: what happened as a sentence, who made it happen and when beneath, and the
/// dollars that moved on the right. A row that came from a post opens it.
struct AccountFeedRow: View {
    let item: AccountFeedItem
    let directory: GuruDirectory
    let isSelected: Bool
    /// Opens the post the row came from; nil when it came from the owner or the post is gone.
    let open: (() -> Void)?
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let open {
            Button(action: open) { content }
                .buttonStyle(QuietPressButtonStyle())
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.sentence)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(highlight, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var highlight: Color {
        if isSelected { return Palette.accent.opacity(0.08) }
        return isHovered && open != nil ? Palette.accent.opacity(0.035) : .clear
    }
}
