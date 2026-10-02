import SwiftUI

/// A connected service: a pale card inside a white frame, its name, what it is
/// set to, and how it is doing.
struct ConnectionTile: View {
    let summary: ConnectionSummary
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fill: Color {
        colorScheme == .dark ? Color(red: 0.13, green: 0.17, blue: 0.21) : Color(red: 0.937, green: 0.973, blue: 0.965)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string(summary.title))
                .font(.system(.body, weight: .semibold).scaled(by: 15.0 / 13))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Text(summary.detail)
                .font(.body)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
            Spacer(minLength: 10)
            Label(summary.status.text, systemImage: summary.status.tone.symbol)
                .font(DesignTokens.caption.weight(.medium))
                .imageScale(.small)
                .foregroundStyle(summary.status.tone == .inactive ? Palette.tertiaryInk : summary.status.tone.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(width: 164, height: 134, alignment: .topLeading)
        .background(fill, in: .rect(cornerRadius: 14))
        .padding(6)
        .background(Palette.page, in: .rect(cornerRadius: 20))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.secondaryInk, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 14 : 8, y: isHovered ? 6 : 3)
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isHovered)
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
