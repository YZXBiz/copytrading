import SwiftUI

/// A setting with a few values, a label over the value with an up-down chevron:
/// the whole row opens the menu. What it changes is a tooltip, not a line under it.
struct SettingsPickerRow<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [Value]
    var hint: String?
    var identifier: String?
    let title: (Value) -> String

    var body: some View {
        Menu {
            Picker(L10n.string(label), selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(L10n.string(title(option))).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            SettingsRow(label: label, title: title(selection)) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
            }
            // One menu button for VoiceOver, named by the label and value below, not one per line.
            .accessibilityElement(children: .ignore)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(L10n.string(label))
        .accessibilityValue(L10n.string(title(selection)))
        .accessibilityHint(hint.map { L10n.string($0) } ?? "")
        .help(hint.map { L10n.string($0) } ?? "")
        .accessibilityIdentifier(identifier ?? label)
    }
}
