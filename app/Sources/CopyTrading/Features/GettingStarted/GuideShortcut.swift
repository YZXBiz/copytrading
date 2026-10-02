/// A keyboard shortcut the guide lists: the keys, in order, and what they do.
struct GuideShortcut: Identifiable {
    let keys: [String]
    let action: String

    var id: String { action }

    static let all: [GuideShortcut] = [
        GuideShortcut(keys: ["⌘", "1", "–", "6"], action: "Go to Today, Activity, People, Accounts, Connections, or this guide"),
        GuideShortcut(keys: ["⌘", "[", "⌘", "]"], action: "Go back and forward"),
        GuideShortcut(keys: ["⌘", "R"], action: "Read accounts and activity again"),
        GuideShortcut(keys: ["⌘", ","], action: "Open Settings"),
        GuideShortcut(keys: ["⌃", "⌘", "S"], action: "Show or hide the sidebar"),
        GuideShortcut(keys: ["↑", "↓"], action: "Move through posts in Activity"),
        GuideShortcut(keys: ["←", "→"], action: "Step through points on Today's chart"),
        GuideShortcut(keys: ["esc"], action: "Clear a measurement on the chart"),
    ]
}
