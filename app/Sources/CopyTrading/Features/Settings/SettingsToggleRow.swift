import SwiftUI

/// A setting that is on or off, with a small switch at the trailing edge.
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var identifier: String?

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle(L10n.string(title), isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier(identifier ?? title)
        }
    }
}
