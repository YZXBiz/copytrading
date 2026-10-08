import SwiftUI

struct ScreenDetailView: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    let activityState: ActivityScreenState
    var body: some View {
        screen
            .sheet(item: $model.setupEditor) { target in
                ConnectionsEditorSheet(target: target, model: model)
            }
            .sheet(isPresented: $model.isShowingSetupCheck) {
                SetupCheckSheet(model: model)
            }
            .onChange(of: model.isShowingSetupCheck) { _, showing in
                // Closing the readings without starting puts the saved setup back to work.
                if !showing { Task { await model.resumeSavedSetupIfPausedForChanges() } }
            }
            .onChange(of: model.setupDraft.signature) {
                model.setupDraftDidChange()
            }
    }

    @ViewBuilder
    private var screen: some View {
        switch model.selectedScreen {
        case .today:
            TodayView(model: model, feature: accountFeature)
        case .activity:
            ActivityView(model: model, feature: accountFeature, screenState: activityState)
        case .people:
            PeopleView(model: model, feature: accountFeature)
        case .accounts:
            AccountsView(model: model, feature: accountFeature)
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
