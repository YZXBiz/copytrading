import Foundation

/// One thing the command palette can do: go to a page, run a safe action, or open a post's guru.
struct PaletteItem: Identifiable {
    enum Kind {
        case page
        case action
        case post
    }

    let id: String
    let kind: Kind
    let title: String
    var detail: String?
    let symbol: String
    let run: @MainActor () -> Void

    /// Whether every word typed appears in the title or detail, in any order, ignoring case.
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return true }
        let text = (title + " " + (detail ?? "")).lowercased()
        return words.allSatisfy { text.contains($0) }
    }
}
