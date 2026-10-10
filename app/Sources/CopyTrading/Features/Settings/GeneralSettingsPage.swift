import SwiftUI

/// What happens when CopyTrading opens: whether it asks for Touch ID, and whether copying starts
/// on its own; whether the Mac stays awake while it copies, and whether each fill is announced.
struct GeneralSettingsPage: View {
    let model: AppModel
    @State private var asksForOwner = true
    @State private var startsCopying = false
    @State private var keepsMacAwake = true
    @AppStorage(FillNotifications.settingKey) private var notifiesFills = true
    @AppStorage(OrderHold.settingKey) private var holdSeconds = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            LanguageSettingsSection()
            TimeZoneSettingsSection()
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
                SettingsToggleRow(
                    title: "Tell me when a trade fills",
                    detail: "A notification with a sound for each copied buy or sell, saying what filled and from whose post.",
                    isOn: $notifiesFills,
                    identifier: "settings.notifiesFills"
                )
                SettingsRow(
                    title: "Hold my orders before sending",
                    detail: "After you press Sell or confirm a copy, the order waits this long with Undo before it leaves for Alpaca."
                ) {
                    HStack(spacing: 18) {
                        ForEach([0.0, 5.0, 10.0], id: \.self) { seconds in
                            ChoiceWord(
                                title: seconds == 0 ? L10n.string("Off") : L10n.string("%lld s", Int64(seconds)),
                                isOn: holdSeconds == seconds
                            ) { holdSeconds = seconds }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(L10n.string("Hold my orders before sending"))
                }
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
