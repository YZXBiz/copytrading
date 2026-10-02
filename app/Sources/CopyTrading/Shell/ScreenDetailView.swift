import SwiftUI

struct ScreenDetailView: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    let activityState: ActivityScreenState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsChangesBar: Bool {
        model.selectedScreen.editsSetup && model.showsSetupChangesBar
    }

    var body: some View {
        screen
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsChangesBar {
                    SetupChangesBar(model: model)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: showsChangesBar)
            .sheet(item: $model.setupEditor) { target in
                ConnectionsEditorSheet(target: target, model: model)
            }
            .sheet(isPresented: $model.isShowingSetupCheck) {
                SetupCheckSheet(model: model)
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
