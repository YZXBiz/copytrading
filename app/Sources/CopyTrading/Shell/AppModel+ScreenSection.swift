extension AppModel {
    /// Sidebar groups, separated by a hairline: the money and the calls first, then the outside
    /// services and the guide below them.
    enum ScreenSection: String, CaseIterable, Identifiable {
        case trading
        case setup

        var id: String { rawValue }

        var screens: [Screen] {
            switch self {
            case .trading: [.today, .activity, .people, .accounts]
            case .setup: [.connections, .gettingStarted]
            }
        }
    }

    /// The plumbing sits out of the way as icon buttons at the foot of the sidebar.
    static let sidebarFooterScreens: [Screen] = [.settings, .diagnostics]
}
