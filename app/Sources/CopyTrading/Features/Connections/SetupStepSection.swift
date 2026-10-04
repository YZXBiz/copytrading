import SwiftUI

/// One step of the setup on Connections: a numbered badge that turns into a green check once the
/// step is done, the step's name and what it is for, and its rows indented under the name.
struct SetupStepSection<Content: View>: View {
    let number: Int
    let isDone: Bool
    var isOptional = false
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                badge
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(DesignTokens.settingsHeading)
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        if isOptional {
                            Text(L10n.string("Optional"))
                                .font(DesignTokens.caption.weight(.medium))
                                .foregroundStyle(Palette.tertiaryInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Palette.well, in: .capsule)
                        }
                    }
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.leading, 32)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isDone)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(isDone ? Color.green : Palette.ink.opacity(0.08))
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(number.formatted())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityElement()
        .accessibilityLabel(isDone ? L10n.string("Step %@, done", number.formatted()) : L10n.string("Step %@", number.formatted()))
    }
}
