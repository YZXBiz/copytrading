import SwiftUI

/// What happens when CopyTrading opens: whether it asks for Touch ID, and whether copying starts
/// on its own.
struct GeneralSettingsPage: View {
    let model: AppModel
    @State private var asksForOwner = true
    @State private var startsCopying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            LanguageSettingsSection()
            SettingsSection(title: "When CopyTrading Opens") {
                SettingsToggleRow(
                    title: "Ask for Touch ID",
                    detail: "Unlock with Touch ID or your Mac's password each time CopyTrading opens.",
                    isOn: $asksForOwner,
                    identifier: "settings.asksForOwner"
                )
                SettingsToggleRow(
                    title: "Start copying automatically",
                    detail: startDetail,
                    isOn: $startsCopying,
                    identifier: "settings.startsCopying"
                )
                .disabled(!model.canStartCopyingOnLaunch)
            }
            SettingsSection(title: "Help") {
                SettingsActionRow(
                    title: "Open Getting Started",
                    detail: "The setup checklist and how a day in CopyTrading goes."
                ) { model.selectedScreen = .gettingStarted }
            }
        }
        .onAppear(perform: load)
        .onChange(of: model.launchPreferences) { load() }
        .onChange(of: asksForOwner) { _, asks in
            // Turning it off asks for Touch ID; a cancelled prompt puts the switch back.
            Task {
                await model.setAsksForOwner(asks)
                load()
            }
        }
        .onChange(of: startsCopying) { _, starts in
            model.setStartsCopying(starts)
        }
    }

    private var startDetail: String {
        model.canStartCopyingOnLaunch
            ? "Runs the same connection checks as Start Copying. Lock still locks."
            : "Only when every account is paper. Lock still locks."
    }

    private func load() {
        asksForOwner = model.launchPreferences.asksForOwner
        startsCopying = model.launchPreferences.startsCopying
    }
}
