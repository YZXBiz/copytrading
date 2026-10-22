import SwiftUI

/// A choice from a longer list in a sheet: the chosen words and a small up-down chevron in the same
/// soft well and width as a field, so it reads as something to click, opening the system menu.
struct SheetMenu<Value: Hashable>: View {
    let label: String
    let choices: [(value: Value, title: String)]
    @Binding var selection: Value
    var width = DesignTokens.sheetFieldWidth

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
                Text(chosen)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: 28)
            .background(Palette.well, in: .rect(cornerRadius: DesignTokens.sheetControlRadius))
            .contentShape(.rect)
            // One menu button for VoiceOver, named by the label and value below, not one per word.
            .accessibilityElement(children: .ignore)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityValue(chosen)
    }

    private var chosen: String {
        choices.first { $0.value == selection }?.title ?? ""
    }
}
