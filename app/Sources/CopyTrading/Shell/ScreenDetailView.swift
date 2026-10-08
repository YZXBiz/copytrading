import SwiftUI

/// The selected screen, with the setup sheets every screen can raise.
struct ScreenDetailView: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    let activityState: ActivityScreenState

    var body: some View {
        screen
            .sheet(item: $model.setupEditor) { ConnectionsEditorSheet(target: $0, model: model) }
            .sheet(isPresented: $model.isShowingSetupCheck) { SetupCheckSheet(model: model) }
            .sheet(item: $model.setupImportResult) { SetupImportSheet(result: $0, model: model) }
            .onChange(of: model.setupDraft.signature) { model.setupDraftDidChange() }
    }

    @ViewBuilder
    private var screen: some View {
        switch model.selectedScreen {
        case .account(let id):
            AccountPage(accountID: id, model: model, feature: accountFeature, activityState: activityState)
                .id(id)
        case .guru(let id):
            GuruPage(guruID: id, model: model, feature: accountFeature)
                .id(id)
        case .connections:
            ConnectionsView(model: model)
        case .gettingStarted:
            GettingStartedView(model: model, feature: accountFeature)
        case .diagnostics:
            DiagnosticsView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }
}
