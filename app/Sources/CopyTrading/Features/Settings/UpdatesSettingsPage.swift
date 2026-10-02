import DesktopCore
import SwiftUI

/// The version on this Mac, and checking, verifying, and installing a newer one.
struct UpdatesSettingsPage: View {
    let model: AppModel

    private var isBusy: Bool {
        model.isCheckingForUpdate || model.isDownloadingUpdate || model.isRunningBackupRestore
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.string("Development build")
    }

    private var visibleStatus: String? {
        guard let status = model.updateMessage, !AppModel.updateProgressMessages.contains(status) else { return nil }
        return status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            SettingsSection(
                title: "CopyTrading",
                subtitle:
                    "A check sends only the app version and platform. Installing rechecks the signature, identity, version, and file hash before the engine stops, and the previous app stays until the new one is ready."
            ) {
                SettingsValueRow(label: "Version on this Mac", value: version)
                SettingsActionRow(title: "Check for Updates", detail: "Looks for a newer release on GitHub.", action: check)
                    .disabled(isBusy)
                if model.isCheckingForUpdate || model.isDownloadingUpdate || model.isInstallingUpdate {
                    SettingsNoteRow(text: model.updateMessage ?? "Working…", isWorking: true)
                } else if let status = visibleStatus {
                    SettingsNoteRow(text: status, tone: status.contains("unavailable") || status.contains("failed") ? .caution : .neutral)
                }
            }

            if let release = model.latestUpdate {
                SettingsSection(title: L10n.string("Release %@", release.version)) {
                    ScrollView {
                        Text(release.notes.isEmpty ? L10n.string("No release notes were provided.") : release.notes)
                            .font(.body)
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(14)
                    }
                    .frame(maxHeight: 180)
                    SettingsActionRow(title: "Download and Verify", action: download)
                        .disabled(isBusy)
                }
            }

            if let staged = model.stagedUpdate {
                SettingsSection(title: "Ready to Install") {
                    SettingsValueRow(label: "Verified download", value: staged.artifactURL.lastPathComponent)
                        .help(staged.artifactURL.path)
                    SettingsActionRow(title: "Install and Relaunch", action: install)
                        .disabled(!model.canInstallStagedUpdate)
                }
            }
        }
    }

    private func check() {
        Task { await model.checkForUpdate() }
    }

    private func download() {
        Task { await model.downloadAndVerifyUpdate() }
    }

    private func install() {
        Task { await model.installStagedUpdate() }
    }
}
