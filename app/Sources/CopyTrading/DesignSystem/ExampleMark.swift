import SwiftUI

/// A small "i" beside a setting's name that opens one worked example of what the number does.
/// The hint under the name says the rule; the example shows it happening.
struct ExampleMark: View {
    let title: String
    let example: String
    @State private var isPresented = false

    var body: some View {
        Button(L10n.string("For example"), systemImage: "info.circle") { isPresented.toggle() }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(L10n.string("For example"))
            .accessibilityLabel(L10n.string("Example: %@", title))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                FloatingPanelSurface(title: L10n.string("For example"), subtitle: title) {
                    Text(localizedMarkdown(example))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 340, alignment: .leading)
                .onExitCommand { isPresented = false }
            }
    }
}
