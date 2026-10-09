import DesktopCore
import SwiftUI

/// One post as a gallery tile on the white page: the guru's words set large, how it was read, what
/// each account did, and the guru's chip on the corner. Hovering draws its ground; choosing it
/// opens the post beside the page.
struct GuruPostCard: View {
    let entry: GuruFeed.Entry
    let guruName: String
    @Binding var selection: SourceActivity.ID?
    /// The top tile of a column sits under the switcher's own line, so it draws none.
    var showsRule = true
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelected: Bool { selection == entry.id }
    private static let quote = DisplayFont.font(size: 24, weight: .regular, relativeTo: .title2)

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 14) {
                if showsRule {
                    Hairline()
                        .padding(.bottom, 10)
                }
                Text(ActivitySourceText.formattedPreview(quoted))
                    .font(Self.quote)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.readAs)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(2)
                GuruAccountOutcomeList(outcomes: entry.accounts, alignment: .leading)
                    .padding(.top, 2)
                // Like a gallery that plays a clip under the pointer: hovering draws the ground and
                // nothing more.
                ZStack(alignment: .bottomLeading) {
                    if isHovered || isSelected {
                        InkGround()
                            .transition(.opacity)
                    }
                    CreditChip(name: guruName, time: time)
                        .padding(.bottom, 10)
                }
                .frame(height: 56, alignment: .bottomLeading)
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isHovered)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
    }

    private var quoted: String {
        let text = entry.item.readableText()
        return text.isEmpty ? L10n.string("No message text") : "“\(text)”"
    }

    /// Today to the second, since calls land seconds apart; the day too for older posts.
    private var time: String {
        guard let date = entry.item.sourceDate else { return "—" }
        return AppTime.calendar.isDateInToday(date)
            ? date.formatted(AppTime.style(.dateTime.hour().minute().second()))
            : Humanize.postTime(date)
    }

    private func toggle() {
        selection = isSelected ? nil : entry.id
    }
}
