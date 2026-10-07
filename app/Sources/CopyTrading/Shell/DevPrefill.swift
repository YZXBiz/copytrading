#if DEBUG
    import DesktopCore
    import Foundation

    /// Debug builds only: `make dev-app` fills an empty Connections from the owner's test keys, so
    /// a first setup can be tried again without typing. The values arrive in a one-time file under
    /// the temporary directory that is read once and deleted. Release bundles compile this out,
    /// and `verify_bundle.py` rejects a binary that contains it.
    struct DevPrefill: Decodable {
        static let variable = "COPYTRADING_DEV_PREFILL"

        var channelID: String
        var discordToken: String
        var provider: TradingProviderName
        var model: String
        var providerAPIKey: String
        var alpacaKey: String
        var alpacaSecret: String
        var guruName: String

        enum CodingKeys: String, CodingKey {
            case channelID = "channel_id"
            case discordToken = "discord_token"
            case provider
            case model
            case providerAPIKey = "provider_api_key"
            case alpacaKey = "alpaca_key"
            case alpacaSecret = "alpaca_secret"
            case guruName = "guru_name"
        }

        /// What this launch was given; the file is gone after the first read.
        static let launch: DevPrefill? = load(environment: ProcessInfo.processInfo.environment)

        private static func load(environment: [String: String]) -> DevPrefill? {
            guard let path = environment[variable] else { return nil }
            guard UITestLaunch.isTemporary(path) else {
                fatalError("\(variable) must name a file under a temporary directory")
            }
            let url = URL(filePath: path)
            let data = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            guard let data, let prefill = try? JSONDecoder().decode(Self.self, from: data) else {
                fatalError("\(variable) names an unreadable file")
            }
            return prefill
        }

        /// Every field the setup asks for: Discord, the interpreter, one paper account, and one
        /// guru on the channel who copies into it.
        func fill(_ draft: inout ConnectionsDraft) {
            draft.channels = channelID
            draft.discordToken = discordToken
            draft.provider = provider
            draft.modelName = model
            draft.providerAPIKey = providerAPIKey
            var account = TradingAccountDraft()
            account.key = alpacaKey
            account.secret = alpacaSecret
            draft.accounts = [account]
            draft.routes = [
                TradingRouteDraft(
                    channelID: channelID, displayName: guruName,
                    connection: TradingConnectionDraft(accountID: account.name))
            ]
        }
    }
#endif
