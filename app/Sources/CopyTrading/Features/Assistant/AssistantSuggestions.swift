/// Four questions to start a conversation with, the first one about the screen the owner is on,
/// in the app's language, so the answer comes back in it too.
enum AssistantSuggestions {
    @MainActor
    static func suggestions(for screen: AppModel.Screen, guru: String?) -> [String] {
        let skipped = L10n.string(screen == .activity ? "Why was this post skipped?" : "Why was the last post skipped?")
        let record = guru.map { L10n.string("How did %@ do this week?", $0) } ?? L10n.string("How did my gurus do this week?")
        let account = L10n.string("What's in my paper account?")
        let alerts = L10n.string("How do I add Telegram alerts?")
        switch screen {
        case .activity: return [skipped, record, account, alerts]
        case .people: return [record, skipped, account, alerts]
        case .accounts: return [account, record, skipped, alerts]
        case .today, .connections, .gettingStarted, .diagnostics, .settings: return [alerts, record, account, skipped]
        }
    }
}
