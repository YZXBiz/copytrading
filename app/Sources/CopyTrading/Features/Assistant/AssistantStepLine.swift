import SwiftUI

/// One quiet line of what the assistant looked at while answering, such as "Checked paper-main";
/// a request the engine refused is marked with a cross instead of a check.
struct AssistantStepLine: View {
    let text: String

    var body: some View {
        let refused = AssistantEngineText.isRefusal(text)
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: refused ? "xmark" : "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(refused ? StatusTone.caution.color : Palette.tertiaryInk.opacity(0.8))
                .accessibilityHidden(true)
            Text(AssistantEngineText.localized(text))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("Step: %@", AssistantEngineText.localized(text)))
        .accessibilityIdentifier("assistant.step")
    }
}
