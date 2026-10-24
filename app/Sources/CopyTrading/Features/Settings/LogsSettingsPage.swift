import AppKit
import DesktopCore
import SwiftUI
import UniformTypeIdentifiers

/// The engine's private log: whether it is writing, how long it is kept, and saving it for support.
struct LogsSettingsPage: View {
    let model: AppModel
    @State private var ageDays = DiagnosticsSettings().ageDays
    @State private var storageLimitBytes = DiagnosticsSettings().storageLimitBytes
    @State private var exportMessage: String?

    private var hasChanges: Bool {
        ageDays != model.diagnosticsSettings.ageDays || storageLimitBytes != model.diagnosticsSettings.storageLimitBytes
    }

    /// A saved change the engine takes on its next start; an edit since then is not saved yet.
    private var waitsForRestart: Bool {
        guard !hasChanges, let applied = model.appliedDiagnosticsSettings, model.engineStatus != nil else { return false }
        return applied != model.diagnosticsSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            SettingsSection(
                title: "Log Health",
                hint: "Each stage, post, model reply, and trade outcome, in a private file on this Mac. Keys are removed first."
            ) {
                if let engine = model.engineStatus {
                    SettingsValueRow(label: "Logging", value: engine.telemetryState.title, tone: engine.telemetryState.tone)
                    if let error = engine.telemetryErrorCode {
                        SettingsNoteRow(text: L10n.string("Last problem: %@", Humanize.code(error)), tone: .caution)
                    }
                    SettingsValueRow(label: "Records dropped", value: engine.telemetryDropped.formatted())
                    SettingsValueRow(
                        label: "Left out (posts / requests / replies)",
                        value:
                            "\(engine.diagnosticCapture.sourceEventGaps) / \(engine.diagnosticCapture.modelRequestGaps) / \(engine.diagnosticCapture.modelResponseGaps)",
                        detail: "A record too large to keep, or one that could not be cleaned of keys safely.")
                } else {
                    SettingsValueRow(label: "Logging", value: L10n.string("Engine stopped"), tone: .inactive)
                }
                SettingsValueRow(label: "On disk", value: Humanize.bytes(model.diagnosticsJournalBytes))
            }

            SettingsSection(
                title: "Log Retention",
                hint: "Oldest days go first. Trading data and backups are never touched."
            ) {
                SettingsRow(label: "Keep logs for", title: Humanize.count(ageDays, "day"), labelsControl: true) {
                    Stepper(
                        L10n.string("Keep logs for"), value: $ageDays,
                        in: DiagnosticsSettings.minimumAgeDays...DiagnosticsSettings.maximumAgeDays
                    )
                    .labelsHidden()
                    .accessibilityValue(Humanize.count(ageDays, "day"))
                    .accessibilityIdentifier("settings.logs.ageDays")
                }
                SettingsPickerRow(
                    label: "Storage limit", selection: $storageLimitBytes, options: DiagnosticsSettings.supportedStorageLimits,
                    identifier: "settings.logs.storageLimit"
                ) { Humanize.bytes($0, style: .memory) }
                if let warning = model.diagnosticsSettingsWarning {
                    SettingsNoteRow(text: warning, tone: .caution)
                }
                SettingsRow(
                    title: waitsForRestart ? "Saved. Applies when the engine next starts." : "Applies when the engine next starts.",
                    titleColor: Palette.secondaryInk
                ) {
                    Button(L10n.string("Save"), action: save)
                        .buttonStyle(PageButtonStyle(emphasis: .prominent))
                        .disabled(!hasChanges)
                        .accessibilityIdentifier("settings.logs.save")
                }
            }

            SettingsSection(title: "Support Export", hint: "Saves the log as a file you choose. Nothing is sent anywhere.") {
                SettingsActionRow(
                    title: "Save Log…",
                    detail: exportMessage ?? L10n.string("Local log, %@", Humanize.bytes(model.diagnosticsJournalBytes)),
                    identifier: "settings.support.saveLog", action: saveLog
                )
                .disabled(model.diagnosticsJournalBytes == 0)
            }
        }
        .task(load)
        .task { await model.reloadDiagnostics() }
    }

    private func load() {
        ageDays = model.diagnosticsSettings.ageDays
        storageLimitBytes = model.diagnosticsSettings.storageLimitBytes
    }

    private func save() {
        model.saveDiagnosticsSettings(ageDays: ageDays, storageLimitBytes: storageLimitBytes)
    }

    private func saveLog() {
        let text: String
        do {
            text = try model.diagnosticsExportText()
        } catch {
            exportMessage = "Could not read the log."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .json]
        panel.nameFieldStringValue = "copytrading-log.jsonl"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            exportMessage = "Saved."
        } catch {
            exportMessage = "Could not save the log."
        }
    }
}
