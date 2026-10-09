import SwiftUI

/// Choices as a row of tracked capitals, like a studio site's navigation, each with an optional
/// count. The chosen one is in ink with a short drawn line under it that slides across when the
/// choice changes, then rests.
struct TrackedSwitcher<Choice: Hashable & Identifiable>: View {
    let choices: [Choice]
    @Binding var selection: Choice
    let title: (Choice) -> String
    var count: (Choice) -> Int = { _ in 0 }
    /// Each choice's identifier is this prefix and the choice's id.
    var identifier = "switcher"
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 32) {
            ForEach(choices) { choice in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { selection = choice }
                } label: {
                    label(choice)
                }
                .buttonStyle(QuietPressButtonStyle())
                .accessibilityAddTraits(choice == selection ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("\(identifier).\(choice.id)")
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func label(_ choice: Choice) -> some View {
        let isSelected = choice == selection
        let number = count(choice)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L10n.string(title(choice)).uppercased())
                    .font(DesignTokens.eyebrow)
                    .tracking(DesignTokens.eyebrowTracking)
                if number > 0 {
                    Text(number.formatted())
                        .font(DesignTokens.eyebrow)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .foregroundStyle(isSelected ? Palette.ink : Palette.tertiaryInk)
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Palette.ink)
                        .frame(height: InkStroke.width)
                        .matchedGeometryEffect(id: "underline", in: underline)
                }
            }
            .frame(height: InkStroke.width)
        }
        .fixedSize()
        .contentShape(.rect)
    }
}
