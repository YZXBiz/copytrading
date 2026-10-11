import DesktopCore

extension ConnectionsDraft {
    /// What Connect still needs for alerts, in the owner's words; nil when it can check. A secret
    /// saved for the same service counts, since a blank field keeps it.
    @MainActor
    func missingForAlerts(savedSecret: Bool) -> String? {
        let hasSecret = !notificationToken.isEmpty || savedSecret
        switch notificationService {
        case .discord:
            return hasSecret ? nil : L10n.string("Paste the channel's webhook URL to connect.")
        case .telegram:
            let missing = [
                notificationChatID.trimmed.isEmpty ? L10n.string("the chat ID") : nil,
                hasSecret ? nil : L10n.string("the bot token"),
            ].compactMap(\.self)
            return missing.isEmpty ? nil : L10n.string("Enter %@ to connect.", L10n.list(missing))
        }
    }
}
