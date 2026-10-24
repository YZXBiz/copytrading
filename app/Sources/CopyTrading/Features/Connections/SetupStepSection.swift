import SwiftUI

/// One step of the setup on Connections: a step number that turns into an ink check once the
/// step is done, the step's name in the display face (what it is for is its tooltip), and its rows
/// under it.
struct SetupStepSection<Content: View>: View {
    let number: Int
    let isDone: Bool
    var isOptional = false
    let title: String
    let hint: String
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                badge
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(DesignTokens.settingsHeading)
                        .tracking(DesignTokens.listHeadingTracking)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                        .help(hint)
                        .accessibilityHint(hint)
                    if isOptional {
                        Text(L10n.string("Optional"))
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.leading, 36)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isDone)
    }

    private var badge: some View {
        ZStack(alignment: .leading) {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(String(format: "%02d", number))
                    .font(DesignTokens.label)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(width: 26, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(L10n.string("Step %@", number.formatted()))
        .accessibilityValue(isDone ? L10n.string("Done") : "")
    }
}
