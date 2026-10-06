import SwiftUI

/// The five steps of a first setup, ticking themselves from what is typed and saved. A step opens
/// its help only when clicked, so the list stays short.
struct SetupChecklist: View {
    @Bindable var model: AppModel
    @State private var expanded: SetupStep?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let progress = model.setupProgress
        VStack(spacing: 2) {
            ForEach(SetupStep.allCases) { step in
                SetupChecklistRow(
                    step: step,
                    isDone: progress.isDone(step),
                    isExpanded: expanded == step,
                    toggle: { toggle(step) },
                    model: model
                )
                if step != SetupStep.allCases.last && expanded != step && expanded != nextStep(after: step) {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
    }

    private func toggle(_ step: SetupStep) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            expanded = expanded == step ? nil : step
        }
    }

    private func nextStep(after step: SetupStep) -> SetupStep? {
        SetupStep(rawValue: step.rawValue + 1)
    }
}
