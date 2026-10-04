/// One service as its Connections tile reads: what it is, what it is set to, and how it is doing.
/// A section without a summary offers its first connection instead.
struct ConnectionSummary: Equatable {
    let title: String
    let detail: String
    let status: ConnectionStatus

    @MainActor
    static func of(_ kind: ConnectionKind, in model: AppModel) -> ConnectionSummary? {
        let draft = model.setupDraft
        let savedKeys = model.hasTradingSecrets
        switch kind {
        case .discord:
            let channels = draft.sourceChannelIDs
            guard !channels.isEmpty else { return nil }
            let authors = ConnectionsDraft.split(draft.authors)
            let who = authors.isEmpty ? L10n.string("anyone who posts") : Humanize.count(authors.count, "author")
            return ConnectionSummary(
                title: "Discord",
                detail: Humanize.joined([Humanize.count(channels.count, "channel"), who]),
                status: ConnectionStatus.discord(model)
                    ?? draftStatus(hasKey: savedKeys || !draft.discordToken.isEmpty, missing: "Needs a token")
            )
        case .interpreter:
            let modelName = draft.modelName.trimmed
            guard !modelName.isEmpty else { return nil }
            return ConnectionSummary(
                title: draft.provider.shortTitle,
                detail: modelName,
                status: ConnectionStatus.interpreter(model)
                    ?? draftStatus(hasKey: model.interpreterHasKey, missing: "Needs an API key")
            )
        case .alerts:
            guard draft.notificationsEnabled else { return nil }
            let savedSecret = savedKeys && model.savedTradingConfiguration?.notification?.service == draft.notificationService
            if draft.notificationService == .discord {
                return ConnectionSummary(
                    title: "Discord",
                    detail: L10n.string("Channel webhook"),
                    status: ConnectionStatus.alerts(model)
                        ?? draftStatus(hasKey: savedSecret || !draft.notificationToken.isEmpty, missing: "Needs a webhook URL")
                )
            }
            let chat = draft.notificationChatID.trimmed
            return ConnectionSummary(
                title: "Telegram",
                detail: chat.isEmpty ? L10n.string("No chat yet") : L10n.string("Chat %@", chat),
                status: ConnectionStatus.alerts(model)
                    ?? draftStatus(hasKey: savedSecret || !draft.notificationToken.isEmpty, missing: "Needs a bot token")
            )
        }
    }

    /// Before a setup is saved a tile can only say whether its key is in.
    @MainActor private static func draftStatus(hasKey: Bool, missing: String) -> ConnectionStatus {
        hasKey ? .init(text: "Not saved yet", tone: .inactive) : .init(text: missing, tone: .caution)
    }
}
