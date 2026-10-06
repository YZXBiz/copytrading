import SwiftUI

/// The version on this Mac, and checking for a newer one. Sparkle shows what is new, downloads
/// it, checks its signature, and relaunches the app once you choose to install.
struct UpdatesSettingsPage: View {
    @Environment(\.appUpdater) private var updater

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.string("Development build")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            SettingsSection(
                title: "CopyTrading",
                subtitle: "A check reads the public list of releases. Nothing about your accounts or trading is sent."
            ) {
                SettingsValueRow(label: "Version on this Mac", value: version)
                SettingsActionRow(
                    title: "Check for Updates…", detail: "Shows what's new and asks before installing.",
                    action: updater.checkForUpdates
                )
                .disabled(!updater.canCheckForUpdates)
                .accessibilityIdentifier("settings.updates.check")
                SettingsToggleRow(
                    title: "Check for updates automatically",
                    detail: "Once a day. You still choose when to install.",
                    isOn: Binding(get: { updater.checksAutomatically }, set: { updater.checksAutomatically = $0 }),
                    identifier: "settings.updates.automatic")
            }
        }
    }
}
