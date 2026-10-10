import DesktopCore
import Foundation

extension AppModel {
    /// What the window shows: one account or one guru, the two primary things the owner works
    /// with, or one of the pages that set them up and look after the app.
    enum Screen: Hashable {
        case account(String)
        case guru(String)
        case connections
        case gettingStarted
        case diagnostics
        case settings

        /// The pages under the accounts and gurus, in sidebar order.
        static let pages: [Screen] = [.connections, .gettingStarted, .settings, .diagnostics]

        var title: String {
            switch self {
            case .account(let id), .guru(let id): id
            case .connections: "Connections"
            case .gettingStarted: "Getting Started"
            case .diagnostics: "Diagnostics"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .account: "building.columns"
            case .guru: "person"
            case .connections: "point.3.connected.trianglepath.dotted"
            case .gettingStarted: "hand.wave"
            case .diagnostics: "waveform.path.ecg"
            case .settings: "gearshape"
            }
        }

        /// The screen an identifier names, as `identifier` spells it.
        init?(identifier: String) {
            let pages: [Screen] = [.connections, .gettingStarted, .diagnostics, .settings]
            if let page = pages.first(where: { $0.identifier == identifier }) {
                self = page
            } else if identifier.hasPrefix("navigation.account.") {
                self = .account(String(identifier.dropFirst("navigation.account.".count)))
            } else if identifier.hasPrefix("navigation.guru.") {
                self = .guru(String(identifier.dropFirst("navigation.guru.".count)))
            } else {
                return nil
            }
        }

        /// The accessibility identifier the sidebar and the UI journeys use.
        var identifier: String {
            switch self {
            case .account(let id): "navigation.account.\(id)"
            case .guru(let id): "navigation.guru.\(id)"
            case .connections: "navigation.connections"
            case .gettingStarted: "navigation.gettingStarted"
            case .diagnostics: "navigation.diagnostics"
            case .settings: "navigation.settings"
            }
        }

        /// The screen's name as the engine's assistant reads it.
        var assistantName: String {
            switch self {
            case .account: "accounts"
            case .guru: "people"
            case .connections: "connections"
            case .gettingStarted: "gettingStarted"
            case .diagnostics: "diagnostics"
            case .settings: "settings"
            }
        }

        var accountID: String? {
            if case .account(let id) = self { id } else { nil }
        }

        var guruID: String? {
            if case .guru(let id) = self { id } else { nil }
        }
    }

    /// Where the window settles: the first saved account, or Getting Started before there is one.
    /// Where the window opens: the page the owner last had open, while it still exists, else
    /// the first account. Settings is never reopened on its own.
    var homeScreen: Screen {
        if let last = Self.rememberedScreen, navigableScreens.contains(last), last != .settings {
            return last
        }
        return savedTradingConfiguration?.accounts.first.map { .account($0.id) } ?? .gettingStarted
    }

    static let lastScreenKey = "window.lastScreen"

    /// The page the owner last had open, kept across launches. The journeys start each run fresh.
    static var rememberedScreen: Screen? {
        #if DEBUG
            if UITestLaunch.hidesTips { return nil }
        #endif
        guard let stored = UserDefaults.standard.string(forKey: lastScreenKey) else { return nil }
        return Screen(identifier: stored)
    }

    /// The selectable screens in sidebar order, for ⌘1… and the page menu.
    var navigableScreens: [Screen] {
        let accounts = savedTradingConfiguration?.accounts.map { Screen.account($0.id) } ?? []
        let gurus = GuruDirectory(savedTradingConfiguration).gurus.map { Screen.guru($0.id) }
        return accounts + gurus + Screen.pages
    }

    /// A screen's name as the owner reads it: a guru by the name they were given.
    func title(of screen: Screen) -> String {
        if let guruID = screen.guruID {
            return GuruDirectory(savedTradingConfiguration).name(for: guruID) ?? guruID
        }
        return screen.accountID ?? L10n.string(screen.title)
    }
}
