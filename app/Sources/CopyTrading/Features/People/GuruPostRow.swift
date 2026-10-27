import DesktopCore
import SwiftUI

/// One post on the guru's timeline: the time to the second in the gutter, the guru's words set large
/// with how they were read, and what each account did in the column on the right. The dot is butter
/// when the post traded. Hovering marks the quote and shows ↗; choosing it opens the post beside
/// the page.
struct GuruPostRow: View {
    let entry: GuruFeed.Entry
    let place: TimelinePlace
    @Binding var selection: SourceActivity.ID?
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sourcePictures) private var pictures

    private var isSelected: Bool { selection == entry.id }
    private static let quote = DisplayFont.font(size: 24, weight: .regular, relativeTo: .title2)

    var body: some View {
        Button(action: toggle) {
            TimelineRow(mark: mark, runsAbove: true, runsBelow: place.runsBelow, isWide: place.isWide, trailingWidth: 300) {
                Text(time)
                    .font(DesignTokens.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
            } content: {
                VStack(alignment: .leading, spacing: 8) {
                    // Under the pointer the quote is marked in butter and the ↗ says it opens.
                    if let picture {
                        // The time and dot sit level with the picture's top, where a quote's first line would be.
                        HStack(alignment: .bottom, spacing: 10) {
                            SourcePictureView(image: picture, maxWidth: 420, maxHeight: 200)
                            OpenArrow(isShown: isHovered || isSelected)
                        }
                        .alignmentGuide(.firstTextBaseline) { $0[.top] + 14 }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(ActivitySourceText.formattedPreview(quoted))
                                .font(Self.quote)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .markerHighlight(isHovered || isSelected)
                            OpenArrow(isShown: isHovered || isSelected)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                        }
                    }
                    Text(entry.readAs)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(2)
                }
            } trailing: {
                GuruAccountOutcomeList(outcomes: entry.accounts, alignment: place.isWide ? .trailing : .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isHovered)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
    }

    /// The post's picture when it has no words of its own.
    private var picture: NSImage? {
        entry.item.readableText().isEmpty ? pictures.firstImage(of: entry.item.sourceEvent) : nil
    }

    private var quoted: String {
        let text = entry.item.readableText()
        return text.isEmpty ? L10n.string("No message text") : "“\(text)”"
    }

    /// The clock to the second, since calls land seconds apart; the day is the label above.
    private var time: String {
        entry.item.sourceDate?.formatted(AppTime.style(.dateTime.hour().minute().second())) ?? "—"
    }

    private var mark: TimelineMark {
        let kinds = entry.accounts.map(\.kind)
        if kinds.contains(.traded) { return .traded }
        if entry.isWaiting { return .waiting }
        if kinds.contains(.working) { return .working }
        return .quiet
    }

    private func toggle() {
        selection = isSelected ? nil : entry.id
    }
}
