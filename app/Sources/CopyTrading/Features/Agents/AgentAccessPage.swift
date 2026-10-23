import AppKit
import DesktopCore
import SwiftUI

/// Whether coding agents may use the `copytrading` CLI and MCP server, how far, and what they
/// asked for.
struct AgentAccessPage: View {
    let model: AppModel
    @State private var copiedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What Copy Setup Command puts on the clipboard, shown whole so the row reads what it copies.
    private var setupCommand: String {
        "claude mcp add copytrading -- \"\(Bundle.main.bundleURL.appending(path: "Contents/Helpers/copytrading").path)\" mcp"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            SettingsSection(
                title: "Allow Agents To",
                subtitle: "Agents such as Claude Code connect through the copytrading command or MCP server while the app runs."
            ) {
                choice("Nothing", detail: nil, .off)
                choice("Read and pause", detail: "Reading needs the app unlocked. Pausing always works.", .readAndPause)
                choice(
                    "Read, pause, and ask for approval",
                    detail: "Anything that could trade waits for your Touch ID here.", .propose)
                if model.agentAccess == .propose {
                    SettingsToggleRow(
                        title: "Allow setup changes from the command line",
                        detail: "copytrading setup may change keys, the model, accounts, and gurus. Live accounts still wait for you.",
                        isOn: Binding(
                            get: { model.agentSetupChanges },
                            set: { allowed in Task { await model.setAgentSetupChanges(allowed) } }),
                        identifier: "agents.setupChanges"
                    )
                    .disabled(model.isChangingAgentAccess)
                }
            }

            SettingsSection(title: "Connection") {
                SettingsValueRow(label: "Status", value: connectionLabel, tone: model.isAgentRelayListening ? .positive : .inactive)
                if model.isAgentRelayListening {
                    SettingsRow(label: "Command", title: setupCommand, detail: "Add it to Claude Code as an MCP server.") {
                        Button(
                            L10n.string(copiedAt == nil ? "Copy Setup Command" : "Copied"),
                            systemImage: copiedAt == nil ? "doc.on.doc" : "checkmark", action: copySetup
                        )
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(copiedAt == nil ? Palette.tertiaryInk : Palette.ink)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .help(L10n.string("Copy the claude mcp add command"))
                        .accessibilityIdentifier("agents.copySetup")
                    }
                    .task(id: copiedAt) {
                        guard copiedAt != nil else { return }
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedAt = nil
                    }
                }
                if let message = model.agentAccessMessage {
                    SettingsNoteRow(text: message, tone: .caution)
                }
            }

            if !model.agentAudit.isEmpty {
                SettingsSection(title: "Recent Requests") {
                    ForEach(model.agentAudit.prefix(10)) { entry in
                        AgentAuditRow(entry: entry)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private var connectionLabel: String {
        if model.agentAccess == .off { return L10n.string("Off") }
        return L10n.string(model.isAgentRelayListening ? "Listening" : "Starts with the engine")
    }

    private func choice(_ title: String, detail: String?, _ setting: AgentAccessSetting) -> some View {
        SettingsChoiceRow(title: title, detail: detail, isSelected: model.agentAccess == setting) {
            Task { await model.setAgentAccess(setting) }
        }
        .disabled(model.isChangingAgentAccess)
    }

    private func copySetup() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setupCommand, forType: .string)
        copiedAt = .now
    }
}
