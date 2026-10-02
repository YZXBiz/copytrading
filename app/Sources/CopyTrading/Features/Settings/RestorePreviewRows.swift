import DesktopCore
import SwiftUI

/// What a backup would restore, before anything changes.
struct RestorePreviewRows: View {
    let model: AppModel
    let preview: RestorePreviewView

    var body: some View {
        SettingsValueRow(
            label: "Same installation", value: L10n.string(preview.matchesInstallation ? "Yes" : "No"),
            tone: preview.matchesInstallation ? .positive : .critical)
        SettingsValueRow(
            label: "Accounts", value: preview.accountIDs.isEmpty ? L10n.string("None") : Humanize.joined(preview.accountIDs))
        SettingsValueRow(
            label: "Environments",
            value: preview.environmentIDs.isEmpty ? L10n.string("None") : Humanize.joined(preview.environmentIDs))
        SettingsValueRow(label: "Backup identity", value: Humanize.revision(preview.installationID, length: 12))
            .help(L10n.string("Installation %@\nStaging %@", preview.installationID, preview.stagingID))
        if let credentials = model.restoreCredentialStatus {
            SettingsNoteRow(text: credentials)
        }
        SettingsNoteRow(
            text:
                "This preview is not active and your current data is unchanged. Broker identity, orders, fills, holdings, and uncertain order IDs must reconcile before the restore can be activated.",
            tone: .caution)
        SettingsActionRow(title: L10n.string("Activate and Reconcile Restore"), action: activate)
            .disabled(!model.canActivateOperationalRestore)
    }

    private func activate() {
        Task { await model.activateOperationalRestore() }
    }
}
