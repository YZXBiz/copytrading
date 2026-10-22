import SwiftUI

/// The last check: each connection's result, with Start Copying once everything passes.
struct SetupCheckSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(
            title: L10n.string("Setup Check"),
            lede: L10n.string("Each connection and what its test found.")
        ) {
            if let report = model.tradingValidation?.report {
                ValidationResultsSection(
                    report: report, modelName: model.setupDraft.modelName,
                    useModel: { model.setupDraft.modelName = $0 },
                    accountPages: Set(model.savedTradingConfiguration?.accounts.map(\.id) ?? []),
                    openAccount: model.openAccountFromSetupCheck, keepAccount: model.keepAccount)
            }
            if model.tradingValidation == nil {
                InkEmptyState(
                    message: L10n.string("Start Copying tests every connection first. The results appear here."))
            }
        } actions: {
            Button(L10n.string("Close"), action: close)
                .buttonStyle(SheetButtonStyle())
                .keyboardShortcut(.cancelAction)
            StartCopyingButton(model: model)
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 460, idealHeight: 640)
    }

    private func close() {
        dismiss()
    }
}
