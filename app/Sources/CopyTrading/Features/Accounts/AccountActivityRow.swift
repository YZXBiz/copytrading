import DesktopCore
import SwiftUI

/// One post in an account's feed: what came of it, who posted what, and when.
struct AccountActivityRow: View {
    let post: SourceActivity
    let outcome: DestinationOutcome
    let guruName: String?
    var isSelected = false

    private var glyph: String {
        switch outcome.tone {
        case .positive: "checkmark"
        case .caution: "hourglass"
        case .critical: "nosign"
        case .neutral: "clock"
        case .inactive: "minus"
        }
    }

    @MainActor private var detail: String {
        var parts: [String] = []
        if let guruName { parts.append(guruName) }
        let text = post.readableText()
        if !text.isEmpty { parts.append("“\(text)”") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ToneGlyph(symbol: glyph, tint: outcome.tone == .inactive ? Palette.tertiaryInk : outcome.tone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.detail)
                    .font(DesignTokens.feedTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(Humanize.feedTime(post.sourceAt))
                .font(DesignTokens.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Palette.accent.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
