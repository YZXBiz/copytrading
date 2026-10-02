import DesktopCore
import SwiftUI

/// One service's settings inside the Connections panel. What is typed goes straight into the
/// setup draft, as everywhere else in the setup, and waits there until the setup is checked.
struct ConnectionEditor: View {
    let kind: ConnectionKind
    @Bindable var model: AppModel
    let done: () -> Void
    /// The field the cursor is in, by its label.
    @FocusState private var focused: String?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var secretPrompt: Text {
        Text(L10n.string(model.hasTradingSecrets ? "Saved in Keychain — leave blank to keep" : "Required"))
    }

    /// The model key: kept when it was saved for this provider, optional for a model run locally.
    private var modelKeyPrompt: Text {
        if model.hasSavedProviderKey { return Text(L10n.string("Saved in Keychain — leave blank to keep")) }
        return Text(L10n.string(model.setupDraft.provider.requiresAPIKey ? "Required" : "Optional for local models"))
    }

    private var baseURLPrompt: Text {
        Text(model.setupDraft.provider == .ollama ? "http://localhost:11434/v1" : "https://…/v1")
    }

    private var help: [HelpArticle] {
        switch kind {
        case .discord: SetupHelp.discord
        case .interpreter: [SetupHelp.interpreterKey(for: model.setupDraft.provider)]
        case .alerts: [SetupHelp.telegram]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                fields
            }
            .background(Palette.page.opacity(reduceTransparency ? 1 : 0.88), in: .rect(cornerRadius: 14))

            HStack(spacing: 12) {
                HelpPopoverButton(articles: help)
                Spacer(minLength: 8)
                if kind == .alerts, model.setupDraft.notificationsEnabled {
                    Button(L10n.string("Turn Off Alerts"), role: .destructive, action: turnOffAlerts)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Button(L10n.string("Done"), action: done)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("connections.done")
            }
            .padding(.horizontal, 4)
        }
        .onAppear { focused = firstField }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.setupDraft.provider.acceptsBaseURL)
    }

    @ViewBuilder
    private var fields: some View {
        switch kind {
        case .discord:
            row("Channel IDs") {
                TextField(
                    L10n.string("Channel IDs"), text: $model.setupDraft.channels,
                    prompt: Text(L10n.string("Comma-separated Discord channel IDs")))
            }
            Divider().padding(.leading, 14)
            row("Allowed authors") {
                TextField(
                    L10n.string("Allowed authors"), text: $model.setupDraft.authors,
                    prompt: Text(L10n.string("Optional, comma-separated user IDs")))
            }
            Divider().padding(.leading, 14)
            row("Discord token") {
                SecureField(L10n.string("Discord token"), text: $model.setupDraft.discordToken, prompt: secretPrompt)
            }
        case .interpreter:
            ConnectionProviderRow(provider: $model.setupDraft.provider)
            Divider().padding(.leading, 14)
            row("Model") {
                TextField(
                    L10n.string("Model"), text: $model.setupDraft.modelName,
                    prompt: Text(SetupHelp.modelExample(for: model.setupDraft.provider)))
            }
            if model.setupDraft.provider.acceptsBaseURL {
                Divider().padding(.leading, 14)
                row("Base URL") {
                    TextField(L10n.string("Base URL"), text: $model.setupDraft.providerBaseURL, prompt: baseURLPrompt)
                }
            }
            Divider().padding(.leading, 14)
            row("API key") {
                SecureField(L10n.string("API key"), text: $model.setupDraft.providerAPIKey, prompt: modelKeyPrompt)
            }
        case .alerts:
            row("Chat ID") {
                TextField(
                    L10n.string("Chat ID"), text: $model.setupDraft.notificationChatID, prompt: Text(L10n.string("From %@", "@userinfobot"))
                )
            }
            Divider().padding(.leading, 14)
            row("Bot token") {
                SecureField(L10n.string("Bot token"), text: $model.setupDraft.notificationToken, prompt: secretPrompt)
            }
        }
    }

    /// One field's row: a click anywhere on it focuses the field, and VoiceOver hears its label.
    private func row(_ label: String, @ViewBuilder field: () -> some View) -> some View {
        ConnectionField(label: label, focus: { focused = label }) {
            field()
                .focused($focused, equals: label)
                .accessibilityLabel(L10n.string(label))
        }
    }

    /// Where the cursor starts when the panel opens.
    private var firstField: String {
        switch kind {
        case .discord: "Channel IDs"
        case .interpreter: "Model"
        case .alerts: "Chat ID"
        }
    }

    /// Clears the chat and the bot token, which turns alerts off as the panel closes.
    private func turnOffAlerts() {
        model.setupDraft.notificationChatID = ""
        model.setupDraft.notificationToken = ""
        done()
    }
}
