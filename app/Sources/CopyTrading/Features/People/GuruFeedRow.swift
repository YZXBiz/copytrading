import DesktopCore
import SwiftUI

/// One of a guru's posts, like a line in a list of works: when it came, what they wrote, how it was
/// read, and what each account did. Choosing it opens the post beside the feed.
struct GuruFeedRow: View {
    let entry: GuruFeed.Entry
    @Binding var selection: SourceActivity.ID?
    @State private var isHovered = false
    @ScaledMetric(relativeTo: .caption) private var timeWidth = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelected: Bool { selection == entry.id }

    var body: some View {
        Button(action: toggle) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    time
                    GuruFeedRowText(entry: entry)
                        .frame(minWidth: 220, alignment: .leading)
                    Spacer(minLength: 16)
                    GuruAccountOutcomeList(outcomes: entry.accounts, alignment: .trailing)
                        .fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    time
                    VStack(alignment: .leading, spacing: 10) {
                        GuruFeedRowText(entry: entry)
                        GuruAccountOutcomeList(outcomes: entry.accounts, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .background(highlight)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
    }

    /// To the second, since a guru's calls can land seconds apart.
    private var time: some View {
        Text(entry.item.sourceDate?.formatted(AppTime.style(.dateTime.hour().minute().second())) ?? "—")
            .font(DesignTokens.caption)
            .monospacedDigit()
            .foregroundStyle(Palette.tertiaryInk)
            .frame(width: timeWidth, alignment: .leading)
    }

    private var highlight: Color {
        if isSelected { return Palette.ink.opacity(0.045) }
        return isHovered ? Palette.ink.opacity(0.025) : .clear
    }

    private func toggle() {
        selection = isSelected ? nil : entry.id
    }
}
