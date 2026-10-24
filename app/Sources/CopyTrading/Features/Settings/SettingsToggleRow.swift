import SwiftUI

/// A setting that is on or off, with a compact switch at the trailing edge. What it does is a
/// tooltip, not a line under it; a line shows only to say why the switch can't be used.
struct SettingsToggleRow: View {
    let title: String
    var hint: String?
    /// Why the switch is off limits right now.
    var detail: String?
    @Binding var isOn: Bool
    var identifier: String?

    var body: some View {
        SettingsRow(title: title, detail: detail, labelsControl: true) {
            Toggle(L10n.string(title), isOn: $isOn)
                .labelsHidden()
                .compactSwitch()
                .accessibilityHint(hint.map { L10n.string($0) } ?? "")
                .accessibilityIdentifier(identifier ?? title)
        }
        .help(hint.map { L10n.string($0) } ?? "")
    }
}
