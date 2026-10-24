import SwiftUI

/// What happens when CopyTrading opens: whether it asks for Touch ID, and whether copying starts
/// on its own; whether the Mac stays awake while it copies, and whether each copied order is announced.
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
                    hint: "Unlock with Touch ID or your Mac's password each time CopyTrading opens.",
                    isOn: $asksForOwner,
                    identifier: "settings.asksForOwner"
                )
                SettingsToggleRow(
                    title: "Start copying automatically",
                    hint: "Runs the same connection checks as Start Copying. Lock still locks.",
                    detail: blockedStart,
                    isOn: $startsCopying,
                    identifier: "settings.startsCopying"
                )
                .disabled(!model.canStartCopyingOnLaunch)
            }
            SettingsSection(title: "While Copying") {
                SettingsToggleRow(
                    title: "Keep this Mac awake",
                    hint: "So no post is missed. The screen can still turn off and lock.",
                    isOn: $keepsMacAwake,
                    identifier: "settings.keepsMacAwake"
                )
                SettingsToggleRow(
                    title: "Tell me when a trade fills",
                    hint: "A notification when each copied order goes out and when it fills.",
                    isOn: $notifiesFills,
                    identifier: "settings.notifiesFills"
                )
                SettingsRow(title: "Hold my orders before sending", labelsControl: true) {
                    Picker(L10n.string("Hold my orders before sending"), selection: $holdSeconds) {
                        ForEach([0.0, 5.0, 10.0], id: \.self) { seconds in
                            Text(seconds == 0 ? L10n.string("Off") : L10n.string("%lld s", Int64(seconds))).tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityHint(L10n.string("Time to undo after you press Sell or confirm a copy."))
                }
                .help(L10n.string("Time to undo after you press Sell or confirm a copy."))
            }
            SettingsSection(title: "Help") {
                SettingsActionRow(
                    title: "Open Getting Started",
                    hint: "The setup checklist and how a day in CopyTrading goes."
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

    /// Why the switch is off limits, when it is: nothing saved yet, or a live account.
    /// Why the switch can't be used yet, the only line the row shows.
    private var blockedStart: String? {
        if model.canStartCopyingOnLaunch { return nil }
        if model.savedTradingConfiguration == nil { return "Once a setup is saved and every account is paper." }
        return "Only when every account is paper."
    }

    private func load() {
        asksForOwner = model.launchPreferences.asksForOwner
        startsCopying = model.launchPreferences.startsCopying
        keepsMacAwake = model.launchPreferences.keepsMacAwake
    }
}
