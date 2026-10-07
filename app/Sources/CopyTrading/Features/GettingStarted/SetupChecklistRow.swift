import SwiftUI

/// One step of the setup checklist. It ticks itself as the setup fills in; clicked, it starts the
/// setup tour, and the step still to do says so at its trailing edge.
struct SetupChecklistRow: View {
    let step: SetupStep
    let isDone: Bool
    let isNext: Bool
    let start: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: start) {
            HStack(alignment: .top, spacing: 14) {
                SetupStepMark(isDone: isDone)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string(step.title))
                        .font(DesignTokens.documentSubheading)
                        .foregroundStyle(isDone ? Palette.secondaryInk : Palette.ink)
                    Text(L10n.string(step.detail))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    if isNext || isHovered {
                        Text(L10n.string("Show Me"))
                            .font(DesignTokens.caption.weight(.medium))
                            .transition(.opacity)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(isNext ? Palette.accent : Palette.tertiaryInk)
                .padding(.top, 4)
                .accessibilityHidden(true)
            }
            .padding(14)
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .background(isHovered ? Palette.group.opacity(0.7) : .clear, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .onHover { hovering in withAnimation(.smooth(duration: 0.15)) { isHovered = hovering } }
        .accessibilityLabel(L10n.string(step.title))
        .accessibilityValue(isDone ? L10n.string("Done") : L10n.string("To do"))
        .accessibilityHint(L10n.string("Shows you where on Connections"))
        .accessibilityIdentifier("guide.step.\(step.id)")
    }
}
