/// A keyboard shortcut the guide lists: the keys, in order, and what they do.
struct GuideShortcut: Identifiable {
    let keys: [String]
    let action: String

    var id: String { action }

    /// What the app's own commands do: Go (⌘1–⌘9 in sidebar order, ⌘K), the window (⌘[ ⌘] ⌘R,
    /// ⌃⌘S), Settings (⌘,), the assistant (⌘J), and the account chart's keys.
    static let all: [GuideShortcut] = [
        GuideShortcut(keys: ["⌘", "1", "–", "9"], action: "Go to an account, a guru, or a page, in sidebar order"),
        GuideShortcut(keys: ["⌘", "K"], action: "Find a post, a guru, or a page"),
        GuideShortcut(keys: ["⌘", "[", "⌘", "]"], action: "Go back and forward"),
        GuideShortcut(keys: ["⌘", "R"], action: "Read accounts and posts again"),
        GuideShortcut(keys: ["⌘", ","], action: "Open Settings"),
        GuideShortcut(keys: ["⌘", "J"], action: "Ask the Assistant"),
        GuideShortcut(keys: ["⌃", "⌘", "S"], action: "Show or hide the sidebar"),
        GuideShortcut(keys: ["←", "→"], action: "Step through points on an account's chart"),
        GuideShortcut(keys: ["esc"], action: "Clear a measurement on the chart"),
    ]
}
