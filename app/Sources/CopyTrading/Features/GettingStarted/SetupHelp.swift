import DesktopCore
import Foundation

/// Where each key and ID comes from. The guide's checklist and the Connections, account, and guru
/// editors all show these same articles.
enum SetupHelp {
    static let channelID = HelpArticle(
        id: "discord.channel",
        title: "Find a channel ID",
        steps: [
            "In Discord, open **User Settings › Advanced** and turn on **Developer Mode**.",
            "Right-click the channel your guru posts in and choose **Copy Channel ID**.",
            "Paste it into **Channel IDs**. Separate several channels with commas.",
        ],
        destination: .init(
            title: "Discord: where to find IDs",
            url: URL(literal: "https://support.discord.com/hc/en-us/articles/206346498-Where-can-I-find-my-User-Server-Message-ID-")
        )
    )

    /// The same steps inside Getting Started, where the field is one click away in Connections.
    static let channelIDInGuide = HelpArticle(
        id: "discord.channel.guide",
        title: "Find a channel ID",
        steps: [
            "In Discord, open **User Settings › Advanced** and turn on **Developer Mode**.",
            "Right-click the channel your guru posts in and choose **Copy Channel ID**.",
            "Click **Open Connections** below.",
            "Under **Discord**, paste it into **Channel IDs**. Separate several channels with commas.",
        ],
        destination: channelID.destination
    )

    static let userID = HelpArticle(
        id: "discord.user",
        title: "Find a guru's user ID",
        intro: "Only needed when several people post in the same channel.",
        steps: [
            "With **Developer Mode** on, right-click the guru's name on one of their posts.",
            "Choose **Copy User ID** and paste it here.",
        ]
    )

    static let discordToken = HelpArticle(
        id: "discord.token",
        title: "Copy your Discord token",
        intro:
            "CopyTrading reads your gurus' channels as you, with your Discord account's token. It works like a password: anyone who has it can use your account.",
        steps: [
            "Open **discord.com/app** in Chrome or Safari and sign in. In Safari, first turn on **Settings › Advanced › Show features for web developers**.",
            "Open the developer tools with **⌥⌘I** and choose the **Network** tab.",
            "Click any channel, then click a request named **messages** in the list.",
            "Under **Request Headers**, copy the value next to **authorization** and paste it into **Discord token**.",
        ],
        caution:
            "Discord's terms don't allow automating personal accounts, and an account can be limited for it. A separate Discord account that only joins your gurus' servers keeps your main account out of it. CopyTrading keeps the token in your Mac's Keychain. Never paste it, or any code someone sends you, anywhere else.",
        destination: .init(title: "Open Discord in your browser", url: URL(literal: "https://discord.com/app"))
    )

    static let alpacaPaperKeys = HelpArticle(
        id: "broker.alpaca",
        title: "Get Alpaca paper keys",
        intro:
            "A paper account trades pretend money at real prices, so you can watch CopyTrading work before any real order. Live keys come from your live account the same way.",
        steps: [
            "Sign up or sign in at **alpaca.markets**. Paper trading is free.",
            "Make sure the account switcher at the top left shows your **Paper** account.",
            "On the home page, find **API Keys** and choose **Generate New Keys**.",
            "Copy the **Key** and the **Secret** into this account. The secret is shown only once.",
        ],
        destination: .init(
            title: "Open your Alpaca paper account", url: URL(literal: "https://app.alpaca.markets/paper/dashboard/overview"))
    )

    static let alpacaLiveKeys = HelpArticle(
        id: "broker.alpaca.live",
        title: "Get Alpaca live keys",
        intro: "Live keys place real orders with real money. Alpaca gives them only to an approved brokerage account.",
        steps: [
            "Sign in at **alpaca.markets**. Live trading needs an approved brokerage account with money in it.",
            "Switch the account switcher at the top left to your **Live** account.",
            "On the home page, find **API Keys** and choose **Generate New Keys**.",
            "Copy the **Key** and the **Secret** into this account. The secret is shown only once.",
        ],
        caution:
            "Anyone with these keys can trade your real money. Set small limits below. New accounts start with entries off, so nothing is bought until you choose **Enable Entries** in **Accounts**.",
        destination: .init(title: "Open Alpaca", url: URL(literal: "https://app.alpaca.markets"))
    )

    /// The keys article for the account's environment: paper and live keys come from different accounts.
    static func alpacaKeys(for environment: TradingEnvironment) -> HelpArticle {
        switch environment {
        case .paper: alpacaPaperKeys
        case .live: alpacaLiveKeys
        }
    }

    static let telegram = HelpArticle(
        id: "alerts.telegram",
        title: "Get Telegram alerts",
        intro: "A bot you make messages you for every order and problem.",
        steps: [
            "In Telegram, message **@BotFather**, send **/newbot**, and follow its steps.",
            "Copy the token it gives you into **Bot token**.",
            "Send your new bot any message, so it's allowed to message you back.",
            "Message **@userinfobot** to get your chat ID, and paste it into **Chat ID**.",
        ],
        destination: .init(title: "Telegram's bot guide", url: URL(literal: "https://core.telegram.org/bots/tutorial"))
    )

    static let discordAlerts = HelpArticle(
        id: "alerts.discord",
        title: "Get Discord alerts",
        intro:
            "CopyTrading posts each alert into a channel through a webhook: no bot, and no token of yours. Anyone with the webhook URL can post in that channel, so keep it like a password.",
        steps: [
            "In Discord, pick a channel only you can see, or make one in a server of your own.",
            "Open the channel's settings, the gear beside its name, then **Integrations › Webhooks › New Webhook**.",
            "Name it CopyTrading, choose **Copy Webhook URL**, and paste it into **Webhook URL**.",
        ],
        destination: .init(
            title: "Discord: intro to webhooks",
            url: URL(literal: "https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks"))
    )

    /// The alerts article for the chosen service.
    static func alerts(for service: TradingAlertService) -> HelpArticle {
        switch service {
        case .telegram: telegram
        case .discord: discordAlerts
        }
    }

    static let guru = HelpArticle(
        id: "people.guru",
        title: "Add a guru",
        steps: [
            "In **Connections**, under **Gurus**, choose **Add a guru** and give them a name.",
            "Pick the channel they post in, then choose **Learn from Channel**. CopyTrading reads their recent posts and drafts how they write buys, sells, and tickers.",
            "Read the playbook and fix anything that's off, such as how they count sells or what their trim words mean. Under **Copies into**, choose their account.",
        ]
    )

    static let start = HelpArticle(
        id: "setup.start",
        title: "Start copying",
        steps: [
            "Choose **Start Copying**. CopyTrading first signs in to Discord, your interpreter, and Alpaca, and reads each example the way it will read real posts.",
            "If anything is marked, choose **Review…**, fix it, then choose **Start Copying** again.",
            "New accounts start with entries off, so nothing is bought until you choose **Enable Entries** in **Accounts**.",
        ]
    )

    /// The how-to the guide shows under each step.
    @MainActor
    static func articles(for step: SetupStep, provider: TradingProviderName) -> [HelpArticle] {
        switch step {
        case .discord: [channelIDInGuide, discordToken]
        case .interpreter: [interpreterKey(for: provider)]
        case .account: [alpacaPaperKeys]
        case .guru: [guru]
        case .start: [start]
        }
    }

    static let discord = [channelID, discordToken, userID]
    @MainActor
    static var all: [HelpArticle] {
        [channelID, userID, discordToken] + interpreters + [alpacaPaperKeys, alpacaLiveKeys, telegram, discordAlerts, guru, start]
    }
}
