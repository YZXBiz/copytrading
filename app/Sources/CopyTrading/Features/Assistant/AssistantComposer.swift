import SwiftUI

/// Where the owner types a question: Return sends it, and a small Stop ends an answer being written.
struct AssistantComposer: View {
    static let characterLimit = 2_000

    @Binding var text: String
    let isAnswering: Bool
    let isEnabled: Bool
    var isFocused: FocusState<Bool>.Binding
    let send: () -> Void
    let stop: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var canSend: Bool {
        isEnabled && !isAnswering && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if text.count > Self.characterLimit - 200 {
                Text(L10n.string("%@ of %@ characters", text.count.formatted(), Self.characterLimit.formatted()))
                    .font(DesignTokens.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.trailing, 6)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    L10n.string(isEnabled ? "Ask about your trading" : "Set up a model in Connections first"), text: $text,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .lineLimit(1...6)
                .focused(isFocused)
                .disabled(!isEnabled)
                .onSubmit(submit)
                .padding(.vertical, 5)
                .accessibilityLabel(L10n.string("Question for the assistant"))
                .accessibilityIdentifier("assistant.composer")
                if isAnswering {
                    Button(action: stop) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(L10n.string("Stop"))
                                .font(DesignTokens.caption.weight(.semibold))
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Palette.well, in: .capsule)
                    }
                    .buttonStyle(QuietPressButtonStyle())
                    .help(L10n.string("Stop this answer"))
                    .accessibilityLabel(L10n.string("Stop answering"))
                    .accessibilityIdentifier("assistant.stop")
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(canSend ? Palette.page : Palette.tertiaryInk)
                            .frame(width: 26, height: 26)
                            .background(canSend ? Palette.ink : Palette.well, in: .circle)
                    }
                    .buttonStyle(QuietPressButtonStyle())
                    .disabled(!canSend)
                    .help(L10n.string("Send"))
                    .accessibilityLabel(L10n.string("Send"))
                    .accessibilityIdentifier("assistant.send")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Palette.page, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline, lineWidth: 1)
            }
        }
        .onChange(of: text) { _, new in
            if new.count > Self.characterLimit { text = String(new.prefix(Self.characterLimit)) }
        }
    }

    private func submit() {
        guard canSend else { return }
        send()
    }
}
