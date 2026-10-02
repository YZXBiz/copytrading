import SwiftUI

/// The last check: each connection's result and how each guru's examples were read, with Start
/// Copying once everything passes.
struct SetupCheckSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !model.profileExampleReviews.isEmpty {
                    ExampleReviewSection(model: model)
                }
                if let report = model.tradingValidation?.report {
                    ValidationResultsSection(report: report)
                }
                if model.profileExampleReviews.isEmpty && model.tradingValidation == nil {
                    ContentUnavailableView(
                        L10n.string("No check results"),
                        systemImage: "checklist",
                        description: Text(L10n.string("Check Setup tests every connection and example. The results appear here."))
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.string("Setup Check"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Close"), action: close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    StartCopyingButton(model: model)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 620)
    }

    private func close() {
        dismiss()
    }
}
