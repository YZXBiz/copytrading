import SwiftUI

/// The five setup steps as a plain numbered list: a tracked number, the step and what it is for,
/// and at the trailing edge either that it is done or, for the next one, the way there. The column
/// of numbers lines the steps up, so space parts them, not rules.
struct GuideStepList: View {
    let progress: SetupProgress
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SetupStep.allCases) { step in
                row(step)
            }
        }
    }

    private func row(_ step: SetupStep) -> some View {
        let isDone = progress.isDone(step)
        let isNext = step == progress.next
        return HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(String(format: "%02d", step.rawValue + 1))
                .font(DesignTokens.eyebrow)
                .tracking(DesignTokens.eyebrowTracking)
                .monospacedDigit()
                .foregroundStyle(isNext ? Palette.ink : Palette.tertiaryInk)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(step.title))
                    .font(DesignTokens.documentSubheading)
                    .foregroundStyle(isDone ? Palette.tertiaryInk : Palette.ink)
                Text(L10n.string(step.detail))
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isDone {
                Label(L10n.string("Done"), systemImage: "checkmark")
                    .font(DesignTokens.eyebrow)
                    .tracking(DesignTokens.eyebrowTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.tertiaryInk)
            } else if isNext {
                Button(L10n.string("Connections"), systemImage: "arrow.right", action: open)
                    .labelStyle(GuideTrailingIconLabelStyle())
                    .buttonStyle(PageButtonStyle())
                    .accessibilityIdentifier("guide.step.next")
            }
        }
        .padding(.vertical, 18)
    }
}
