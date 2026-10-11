import SwiftUI

/// Choices as a row of tracked capitals, like a studio site's navigation, each with an optional
/// count. The chosen one is in ink with a short drawn line under it, the only line here, that
/// slides across when the choice changes, then rests. Control-1, Control-2… pick a choice from the
/// keyboard; Command-1, 2… stay the sidebar's. One switcher per page, so the keys are its.
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
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { selection = choice }
                } label: {
                    label(choice)
                }
                .buttonStyle(QuietPressButtonStyle())
                // A switcher has at most a handful of choices, so each gets a digit.
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                .help(L10n.string("%@ (Control-%lld)", L10n.string(title(choice)), Int64(index + 1)))
                .accessibilityAddTraits(choice == selection ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("\(identifier).\(choice.id)")
            }
            Spacer(minLength: 0)
        }
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
