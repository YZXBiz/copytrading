/// The engine writes its step lines and errors in English. The app shows them from its own
/// catalogs, so "Read paper-main's history" reads as "已读取 paper-main 的账户历史记录" in 简体中文;
/// a line the catalogs don't know stays as the engine wrote it.
enum AssistantEngineText {
    /// Step lines that name one account or guru, as catalog keys; a refused request has its own
    /// "Couldn't …" line.
    static let templates = [
        "Couldn't read %@'s history", "Couldn't pause new entries for %@",
        "Couldn't ask you to approve resuming %@", "Couldn't ask you to approve %@'s after-restart setting",
        "Read %@'s history", "Paused new entries for %@", "Asked you to approve resuming %@",
        "Asked you to approve %@'s after-restart setting", "Added up %@'s calls",
    ]

    /// The engine starts every step line for a refused request with "Couldn't".
    static func isRefusal(_ step: String) -> Bool { step.hasPrefix("Couldn't ") }

    @MainActor
    static func localized(_ text: String) -> String {
        for template in templates {
            let parts = template.components(separatedBy: "%@")
            guard parts.count == 2 else { continue }
            let (prefix, suffix) = (parts[0], parts[1])
            guard text.count > prefix.count + suffix.count, text.hasPrefix(prefix), text.hasSuffix(suffix) else {
                continue
            }
            return L10n.string(template, String(text.dropFirst(prefix.count).dropLast(suffix.count)))
        }
        return L10n.string(text)
    }
}
