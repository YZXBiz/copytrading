import SwiftUI

/// The five steps of a first setup, ticking themselves from what is typed and saved. Each one
/// starts the setup tour, which walks Connections to the first thing still to do.
struct SetupChecklist: View {
    @Bindable var model: AppModel

    var body: some View {
        let progress = model.setupProgress
        VStack(spacing: 2) {
            ForEach(SetupStep.allCases) { step in
                SetupChecklistRow(
                    step: step, isDone: progress.isDone(step), isNext: progress.next == step, start: model.startSetupTour)
                if step != SetupStep.allCases.last {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
    }
}
