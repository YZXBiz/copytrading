import AppKit
import DesktopCore
import SwiftUI

/// Whether coding agents may use the `copytrading` CLI and MCP server, how far, and what they
/// asked for.
struct AgentAccessPage: View {
    let model: AppModel

    private var command: String {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/copytrading").path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            SettingsSection(
                title: "Allow Agents To",
                subtitle:
                    "Coding agents such as Claude Code reach CopyTrading through its copytrading command or MCP server, and only while the app runs. Posts from sources reach them as untrusted text."
            ) {
                choice("Nothing", detail: nil, .off)
                choice("Read and pause", detail: "Reading needs the app unlocked. Pausing always works.", .readAndPause)
                choice(
                    "Read, pause, and ask for approval",
                    detail: "Anything that could trade only becomes a request you approve here with Touch ID.", .propose)
            }

            SettingsSection(title: "Connection") {
                SettingsValueRow(label: "Status", value: connectionLabel, tone: model.isAgentRelayListening ? .positive : .inactive)
                if model.isAgentRelayListening {
                    SettingsRow(label: "Command", title: command, detail: "Add it to Claude Code as an MCP server.") {
                        Button(L10n.string("Copy Setup Command"), systemImage: "doc.on.doc", action: copySetup)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(Palette.tertiaryInk)
                            .help(L10n.string("Copy the claude mcp add command"))
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
        NSPasteboard.general.setString("claude mcp add copytrading -- \"\(command)\" mcp", forType: .string)
    }
}
