import SwiftUI

/// An empty Connections section: one wide white card offering the first connection.
struct ConnectionAddCard: View {
    let title: String
    let subtitle: String
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fill: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.16, blue: 0.18) : Color(red: 0.988, green: 0.984, blue: 0.976)
    }

    var body: some View {
        VStack(spacing: 5) {
            Label(L10n.string(title), systemImage: "plus.square")
                .font(.system(.body, weight: .medium).scaled(by: 15.0 / 13))
                .foregroundStyle(Palette.ink)
            Text(L10n.string(subtitle))
                .font(.body)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(fill, in: .rect(cornerRadius: 14))
        .padding(5)
        .background(Palette.page, in: .rect(cornerRadius: 19))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 19).strokeBorder(Palette.secondaryInk, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(isHovered ? 0.09 : 0.04), radius: isHovered ? 14 : 8, y: isHovered ? 5 : 3)
        .scaleEffect(isHovered && !reduceMotion ? 1.005 : 1)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isHovered)
        .contentShape(.rect(cornerRadius: 19))
        .accessibilityElement(children: .combine)
    }
}
