import SwiftUI

/// The five steps of a first setup, ticking themselves from what is typed and saved. The next step
/// to do is open; finishing it opens the one after.
struct SetupChecklist: View {
    @Bindable var model: AppModel
    @State private var expanded: SetupStep?
    @State private var hasOpenedNext = false
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
        .onAppear(perform: openNextStep)
        .onChange(of: progress.next) { previous, next in
            follow(from: previous, to: next)
        }
    }

    private func toggle(_ step: SetupStep) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            expanded = expanded == step ? nil : step
        }
    }

    /// Opens the first unfinished step once, when the guide first appears.
    private func openNextStep() {
        guard !hasOpenedNext else { return }
        hasOpenedNext = true
        expanded = model.setupProgress.next
    }

    /// When the open step gets done, the next one opens, so the guide keeps pace with the owner.
    private func follow(from previous: SetupStep?, to next: SetupStep?) {
        guard expanded == previous else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            expanded = next
        }
    }

    private func nextStep(after step: SetupStep) -> SetupStep? {
        SetupStep(rawValue: step.rawValue + 1)
    }
}
