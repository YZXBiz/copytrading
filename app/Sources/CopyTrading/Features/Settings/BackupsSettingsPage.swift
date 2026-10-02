import AppKit
import DesktopCore
import SwiftUI
import UniformTypeIdentifiers

/// Where CopyTrading keeps its records, and backing them up or restoring them.
struct BackupsSettingsPage: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            SettingsSection(title: "Data Folder", subtitle: "Everything CopyTrading records stays here, on this Mac.") {
                DataFolderRow(path: model.operationalStoragePath)
            }

            SettingsSection(
                title: "Backup & Restore",
                subtitle:
                    "A backup holds your records, saved setup, captured posts, and attachments. Keys and disposable logs are left out."
            ) {
                SettingsActionRow(
                    title: "Create Backup…", detail: "Pauses and drains trading writers while it runs.", action: chooseBackupDestination
                )
                .disabled(model.isRunningBackupRestore)
                SettingsActionRow(
                    title: "Restore from Backup…", detail: "Shows what a backup holds first. Nothing changes until you activate it.",
                    action: chooseRestoreArchive
                )
                .disabled(model.isRunningBackupRestore || model.pendingRestoreCandidate != nil)
                if model.isRunningBackupRestore {
                    SettingsNoteRow(text: model.backupRestoreMessage ?? "Working…", isWorking: true)
                } else if let status = model.backupRestoreMessage {
                    SettingsNoteRow(text: status, tone: status.contains("failed") || status.contains("could not") ? .caution : .neutral)
                }
                if let recovery = model.restoreRecoveryMessage {
                    SettingsNoteRow(text: recovery, tone: .caution)
                }
                if let manifest = model.backupManifest {
                    SettingsValueRow(
                        label: "Last verified backup",
                        value: "\(Humanize.timestamp(manifest.createdAt)) · \(Humanize.count(manifest.members.count, "file"))")
                }
            }

            if let preview = model.restorePreview {
                SettingsSection(title: "Restore Preview") {
                    RestorePreviewRows(model: model, preview: preview)
                }
            }
            if let pending = model.pendingRestoreCandidate {
                SettingsSection(title: "Restore in Progress") {
                    PendingRestoreRows(model: model, pending: pending)
                }
            }
            if !model.restorePreflightBlockers.isEmpty {
                SettingsSection {
                    SettingsNoteRow(
                        text: L10n.string(
                            "Before it can restore: %@", Humanize.joined(model.restorePreflightBlockers.map(Humanize.code))),
                        tone: .caution)
                }
            }
        }
    }

    private func chooseBackupDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "CopyTrading-Backup.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { await model.createOperationalBackup(to: destination) }
    }

    private func chooseRestoreArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let archive = panel.url else { return }
        Task { await model.previewOperationalRestore(from: archive) }
    }
}
