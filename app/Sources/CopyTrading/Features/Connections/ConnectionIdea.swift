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
}
