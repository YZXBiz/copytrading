import SwiftUI

/// One step of the setup checklist. It ticks itself as the setup fills in; opened, it shows where
/// to find what the step needs and the button that goes there.
struct SetupChecklistRow: View {
    let step: SetupStep
    let isDone: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(QuietPressButtonStyle())
            .accessibilityLabel(L10n.string(step.title))
            .accessibilityValue(isDone ? L10n.string("Done") : L10n.string("To do"))
            .accessibilityHint(isExpanded ? L10n.string("Hides how to do this step") : L10n.string("Shows how to do this step"))
            .accessibilityIdentifier("guide.step.\(step.id)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(SetupHelp.articles(for: step, provider: model.setupDraft.provider)) { article in
                        HelpArticleView(article: article)
                    }
                    SetupStepAction(step: step, isDone: isDone, model: model)
                }
                .padding(.leading, 50)
                .padding(.trailing, 18)
                .padding(.bottom, 20)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isExpanded ? Palette.group.opacity(0.7) : .clear, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .clipShape(.rect(cornerRadius: DesignTokens.blockCornerRadius))
    }
}
