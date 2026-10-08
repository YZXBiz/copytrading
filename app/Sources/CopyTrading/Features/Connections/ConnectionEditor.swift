import DesktopCore
import SwiftUI

/// One service's settings inside the Connections panel. What is typed goes straight into the
/// setup draft and waits there until copying starts. Connect checks the service there and then:
/// the panel closes once it answers, and says what is wrong when it doesn't.
struct ConnectionEditor: View {
    let kind: ConnectionKind
    @Bindable var model: AppModel
    /// Connect for a service not set up when the sheet opened; Save for one being edited.
    let isNew: Bool
    let done: () -> Void
    /// The field the cursor is in, by its label.
    @FocusState private var focused: String?
    @State private var isChecking = false

    private var subject: ConnectionCheckSubject { ConnectionCheckSubject(kind) }

    /// The latest check, while it failed and nothing it checked has been edited since.
    private var failedCheck: TradingCapabilityCheck? {
        guard let check = model.connectionCheckResult(subject)?.check, check.state == .failed else { return nil }
        return check
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A saved alert secret is kept only for the service it was saved for.
    private func alertSecretPrompt(otherwise: String) -> Text {
        let saved = model.savedTradingConfiguration?.notification?.service == model.setupDraft.notificationService
        return Text(L10n.string(model.hasTradingSecrets && saved ? "Saved in Keychain — leave blank to keep" : otherwise))
    }

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

    /// Where this service's key comes from, at the top of the sheet.
    private var guide: HelpArticle {
        switch kind {
        case .discord: SetupHelp.discordToken
        case .interpreter: SetupHelp.interpreterKey(for: model.setupDraft.provider)
        case .alerts: SetupHelp.alerts(for: model.setupDraft.notificationService)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ConnectionGuideCard(article: guide)
            VStack(alignment: .leading, spacing: 14) {
                fields
            }
            if let failedCheck {
                ConnectionCheckCallout(
                    check: failedCheck, modelName: model.setupDraft.modelName,
                    useModel: kind == .interpreter ? { model.setupDraft.modelName = $0 } : nil)
            }
            VStack(spacing: 10) {
                Button(action: connect) {
                    HStack(spacing: 8) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(L10n.string(isChecking ? "Checking…" : isNew ? "Connect" : "Save"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(isChecking)
                .accessibilityIdentifier("connections.done")
                if kind == .alerts, model.setupDraft.notificationsEnabled {
                    Button(L10n.string("Turn Off Alerts"), role: .destructive, action: turnOffAlerts)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
            }
        }
        // Focus waits until the panel has grown out of its row: a field focused mid-animation is
        // marked focused without ever getting the keyboard, and then a click on it changes nothing.
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 450))
            focused = firstField
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.setupDraft.provider.acceptsBaseURL)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: failedCheck)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.setupTourStop)
    }

    @ViewBuilder
    private var fields: some View {
        switch kind {
        case .discord:
            toured(.channelIDs) {
                row("Channel IDs") {
                    TextField(
                        L10n.string("Channel IDs"), text: $model.setupDraft.channels,
                        prompt: Text(L10n.string("Comma-separated Discord channel IDs")))
                }
            }
            row("Allowed authors") {
                TextField(
                    L10n.string("Allowed authors"), text: $model.setupDraft.authors,
                    prompt: Text(L10n.string("Optional, comma-separated user IDs")))
            }
            toured(.discordToken) {
                row("Discord token") {
                    SecureField(L10n.string("Discord token"), text: $model.setupDraft.discordToken, prompt: secretPrompt)
                }
            }
        case .interpreter:
            row("Model") {
                TextField(
                    L10n.string("Model"), text: $model.setupDraft.modelName,
                    prompt: Text(SetupHelp.modelExample(for: model.setupDraft.provider)))
            }
            if model.setupDraft.provider.acceptsBaseURL {
                row("Base URL") {
                    TextField(L10n.string("Base URL"), text: $model.setupDraft.providerBaseURL, prompt: baseURLPrompt)
                }
            }
            toured(.interpreterKey) {
                row("API key") {
                    SecureField(L10n.string("API key"), text: $model.setupDraft.providerAPIKey, prompt: modelKeyPrompt)
                }
            }
        case .alerts where model.setupDraft.notificationService == .discord:
            row("Webhook URL") {
                SecureField(
                    L10n.string("Webhook URL"), text: $model.setupDraft.notificationToken,
                    prompt: alertSecretPrompt(otherwise: "https://discord.com/api/webhooks/…"))
            }
        case .alerts:
            row("Chat ID") {
                TextField(
                    L10n.string("Chat ID"), text: $model.setupDraft.notificationChatID, prompt: Text(L10n.string("From %@", "@userinfobot"))
                )
            }
            row("Bot token") {
                SecureField(
                    L10n.string("Bot token"), text: $model.setupDraft.notificationToken, prompt: alertSecretPrompt(otherwise: "Required"))
            }
        }
    }

    /// A field the setup tour can point at. While it does, the field and the tour's hint share
    /// one outlined card inside the panel's column.
    private func toured(_ stop: SetupTourStop, @ViewBuilder field: () -> some View) -> some View {
        let active = model.setupTourStop == stop
        return VStack(alignment: .leading, spacing: 12) {
            field()
            if active {
                SetupTourInlineHint(stop: stop, model: model)
                    .transition(.opacity)
            }
        }
        .padding(active ? 12 : 0)
        .background {
            if active {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.accent.opacity(0.07))
                    .strokeBorder(Palette.accent.opacity(0.6), lineWidth: 1.5)
            }
        }
        .setupTourTarget(stop.target)
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
        case .alerts: model.setupDraft.notificationService == .discord ? "Webhook URL" : "Chat ID"
        }
    }

    /// Checks the service as typed. The panel closes when it answers, or when there is nothing the
    /// engine can check yet; a failed check stays on screen until something is changed.
    private func connect() {
        if kind == .alerts {
            let draft = model.setupDraft
            model.setupDraft.notificationsEnabled = !draft.notificationChatID.trimmed.isEmpty || !draft.notificationToken.isEmpty
        }
        Task {
            isChecking = true
            let check = await model.checkConnection(subject)
            isChecking = false
            if check?.state != .failed { done() }
        }
    }

    /// Clears the chat and the bot token, which turns alerts off as the panel closes.
    private func turnOffAlerts() {
        model.setupDraft.notificationChatID = ""
        model.setupDraft.notificationToken = ""
        done()
    }
}
