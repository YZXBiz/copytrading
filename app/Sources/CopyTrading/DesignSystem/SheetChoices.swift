import SwiftUI

/// A few choices in a sheet as words in tracked capitals, the chosen one in ink with a short ink
/// line under it. No segmented box, no capsules.
struct SheetChoices<Value: Hashable>: View {
    /// What the choice is about, for VoiceOver.
    let label: String
    let choices: [(value: Value, title: String)]
    @Binding var selection: Value
    /// Each choice's identifier is this prefix, a dot, and its position.
    var identifier = "sheet.choice"
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 28) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                let isSelected = choice.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selection = choice.value }
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(choice.title.uppercased())
                            .font(DesignTokens.eyebrow)
                            .tracking(DesignTokens.eyebrowTracking)
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
                .buttonStyle(QuietPressButtonStyle())
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("\(identifier).\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
