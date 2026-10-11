import SwiftUI

/// The sparkle at the end of the toolbar that opens and closes the assistant.
struct AssistantToolbarButton: View {
    let assistant: AssistantModel

    var body: some View {
        Button(L10n.string(assistant.isOpen ? "Close the Assistant" : "Ask the Assistant"), systemImage: "sparkle") {
            assistant.isOpen.toggle()
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(Palette.ink)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(L10n.string(assistant.isOpen ? "Close the Assistant" : "Ask the Assistant (⌘J)"))
        .accessibilityIdentifier("toolbar.assistant")
    }
}
