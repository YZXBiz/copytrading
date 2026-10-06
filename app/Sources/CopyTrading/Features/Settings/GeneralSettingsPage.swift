import SwiftUI

/// What happens when CopyTrading opens: whether it asks for Touch ID, and whether copying starts
/// on its own; and whether the Mac stays awake while it copies.
struct GeneralSettingsPage: View {
    let model: AppModel
    @State private var asksForOwner = true
    @State private var startsCopying = false
    @State private var keepsMacAwake = true

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
            SettingsSection(title: "While Copying") {
                SettingsToggleRow(
                    title: "Keep this Mac awake",
                    detail:
                        "So no post is missed. The screen can still turn off and lock. Closing a MacBook's lid still puts it to sleep unless it's plugged in with a display connected.",
                    isOn: $keepsMacAwake,
                    identifier: "settings.keepsMacAwake"
                )
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
        .onChange(of: keepsMacAwake) { _, keeps in
            model.setKeepsMacAwake(keeps)
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
        keepsMacAwake = model.launchPreferences.keepsMacAwake
    }
}
