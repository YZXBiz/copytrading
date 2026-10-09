import SwiftUI

/// A choice from a longer list in a sheet: the chosen words and a small chevron on the same
/// underline as a field, opening the system menu. No popup-button box.
struct SheetMenu<Value: Hashable>: View {
    let label: String
    let choices: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Button {
                    selection = choice.value
                } label: {
                    if choice.value == selection {
                        Label(choice.title, systemImage: "checkmark")
                    } else {
                        Text(choice.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(choices.first { $0.value == selection }?.title ?? "")
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
    }
}
