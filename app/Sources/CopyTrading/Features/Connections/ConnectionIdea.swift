import DesktopCore
import SwiftUI

/// The how-tos Connections suggests under its sections as "Setup Tips". Each opens the same steps
/// the guide shows.
enum ConnectionIdea: String, CaseIterable, Identifiable {
    case channelID
    case discordToken
    case interpreterKey
    case telegram

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .channelID: L10n.string("Find a Channel ID")
        case .discordToken: L10n.string("Copy Your Token")
        case .interpreterKey: L10n.string("Get an API Key")
        case .telegram: L10n.string("Alerts on Your Phone")
        }
    }

    @MainActor var blurb: String {
        switch self {
        case .channelID: L10n.string("Turn on Developer Mode, then right-click the channel your guru posts in and copy its ID.")
        case .discordToken: L10n.string("CopyTrading reads channels as you. Your token lets it, and stays in your Keychain.")
        case .interpreterKey: L10n.string("Your interpreter bills you for what it reads. A key takes a minute to make.")
        case .telegram: L10n.string("A bot messages you for every order and every problem, wherever you are.")
        }
    }

    @MainActor
    func article(for provider: TradingProviderName) -> HelpArticle {
        switch self {
        case .channelID: SetupHelp.channelID
        case .discordToken: SetupHelp.discordToken
        case .interpreterKey: SetupHelp.interpreterKey(for: provider)
        case .telegram: SetupHelp.telegram
        }
    }

    /// Each idea has its own tint: peach, lilac, mint, and sky.
    func tint(dark: Bool) -> Color {
        switch (self, dark) {
        case (.channelID, false): Color(red: 1.0, green: 0.969, blue: 0.941)
        case (.discordToken, false): Color(red: 0.961, green: 0.949, blue: 0.996)
        case (.interpreterKey, false): Color(red: 0.945, green: 0.98, blue: 0.949)
        case (.telegram, false): Color(red: 0.941, green: 0.969, blue: 0.996)
        case (.channelID, true): Color(red: 0.2, green: 0.17, blue: 0.15)
        case (.discordToken, true): Color(red: 0.18, green: 0.17, blue: 0.22)
        case (.interpreterKey, true): Color(red: 0.15, green: 0.19, blue: 0.16)
        case (.telegram, true): Color(red: 0.14, green: 0.18, blue: 0.22)
        }
    }
}
