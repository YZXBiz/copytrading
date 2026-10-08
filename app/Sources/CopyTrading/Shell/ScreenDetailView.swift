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
            .sheet(item: $model.setupImportResult) { result in
                SetupImportSheet(result: result, model: model)
            }
            .onChange(of: model.setupDraft.signature) {
                model.setupDraftDidChange()
            }
    }

    /// The guru People shows: the one last opened while they are still saved, else the first.
    private var peopleGuruID: String? {
        let gurus = GuruDirectory(model.savedTradingConfiguration).gurus
        return gurus.first { $0.id == model.openGuruID }?.id ?? gurus.first?.id
    }

    private func openConnections() {
        model.selectedScreen = .connections
    }

    @ViewBuilder
    private var screen: some View {
        switch model.selectedScreen {
        case .today:
            TodayView(model: model, feature: accountFeature)
        case .activity:
            ActivityView(model: model, feature: accountFeature, screenState: activityState)
        case .people:
            if let guruID = peopleGuruID {
                GuruPage(guruID: guruID, model: model, feature: accountFeature)
            } else {
                ScrollView {
                    PeopleInvitation(
                        hasUnsavedGurus: model.setupDraft.routes.contains { !$0.displayName.trimmed.isEmpty },
                        openConnections: openConnections
                    )
                    .padding(DesignTokens.pagePadding)
                }
            }
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
