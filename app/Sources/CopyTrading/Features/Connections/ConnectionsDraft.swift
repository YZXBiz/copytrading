import DesktopCore
import Foundation

/// The editable, unsaved form of a trading configuration plus the secrets typed into it.
struct ConnectionsDraft {
    var channels = ""
    var authors = ""
    var discordToken = ""
    var provider: TradingProviderName = .anthropic
    var modelName = ""
    /// Where an Ollama or OpenAI-compatible model is served; ignored for the other providers.
    var providerBaseURL = ""
    var providerAPIKey = ""
    var accounts: [TradingAccountDraft] = []
    var routes: [TradingRouteDraft] = []
    var notificationsEnabled = false
    var notificationService = TradingAlertService.telegram
    var notificationChatID = ""
    /// Telegram's bot token, or a Discord channel's webhook URL.
    var notificationToken = ""

    var hasLiveAccounts: Bool {
        accounts.contains { $0.environment == .live }
    }

    /// Nothing has been entered yet: a first run that has not started.
    var isEmpty: Bool {
        channels.trimmed.isEmpty && authors.trimmed.isEmpty && modelName.trimmed.isEmpty
            && providerBaseURL.trimmed.isEmpty
            && accounts.isEmpty && routes.isEmpty && !notificationsEnabled && !hasTypedSecrets
    }

    /// Keys typed into the draft that are not saved yet.
    var hasTypedSecrets: Bool {
        !discordToken.isEmpty || !providerAPIKey.isEmpty || !notificationToken.isEmpty
            || accounts.contains { !$0.key.isEmpty || !$0.secret.isEmpty }
    }

    /// What a check covers: the configuration it would save and a digest of the typed keys, so
    /// a change to either after a check discards that check.
    var signature: SetupDraftSignature {
        var keys = Hasher()
        keys.combine(discordToken)
        keys.combine(providerAPIKey)
        keys.combine(notificationToken)
        for account in accounts {
            keys.combine(account.key)
            keys.combine(account.secret)
        }
        return SetupDraftSignature(configuration: try? submission().0, typedKeys: keys.finalize())
    }

    /// "primary" for the first account, then "account-2", "account-3", … skipping names in use.
    var nextAccountName: String {
        let used = Set(accounts.map { $0.name.trimmed })
        if !used.contains("primary") { return "primary" }
        var number = 2
        while used.contains("account-\(number)") { number += 1 }
        return "account-\(number)"
    }

    var sourceChannelIDs: [String] { Self.split(channels) }

    /// A route without its own channel follows the first source channel, resolved when shown and
    /// when submitted, so a one-channel setup needs the channel entered only once.
    func effectiveChannel(for route: TradingRouteDraft) -> String {
        let own = route.channelID.trimmed
        return own.isEmpty ? sourceChannelIDs.first ?? "" : own
    }

    var accountIDs: [String] {
        accounts.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    mutating func load(_ saved: TradingConfiguration) {
        channels = saved.source.channelIDs.joined(separator: ", ")
        authors = saved.source.authorIDs.joined(separator: ", ")
        provider = saved.provider.name
        modelName = saved.provider.model
        providerBaseURL = saved.provider.baseURL ?? ""
        accounts = saved.accounts.map {
            TradingAccountDraft(name: $0.id, environment: $0.environment, policy: $0.policy)
        }
        let profileByRevision = Dictionary(
            uniqueKeysWithValues: saved.profiles.map { ($0.profileRevision, $0) }
        )
        routes = saved.routes.map { route in
            let profile = profileByRevision[route.profileRevision]
            return TradingRouteDraft(
                channelID: route.channelID,
                authorID: route.authorID ?? "",
                guruID: route.guruID,
                displayName: profile?.displayName ?? route.guruID,
                prefix: profile?.prefix ?? "ALERT:",
                playbook: profile?.playbook ?? "",
                exitBasis: profile?.exitBasis ?? .originalPosition,
                examples: profile?.examples.map(TradingProfileExampleDraft.init(example:)) ?? [],
                connections: route.connections.map { connection in
                    TradingConnectionDraft(
                        accountID: connection.accountID, amountUSD: connection.amountUSD,
                        defaultFraction: connection.defaultFraction
                    )
                }
            )
        }
        notificationsEnabled = saved.notification != nil
        notificationService = saved.notification?.service ?? .telegram
        notificationChatID = saved.notification?.chatID ?? ""
    }

    mutating func clearSecrets() {
        discordToken = ""
        providerAPIKey = ""
        notificationToken = ""
        for index in accounts.indices {
            accounts[index].key = ""
            accounts[index].secret = ""
        }
    }

    /// The interpreter as it would be saved: a base URL travels only for a provider that takes one.
    var providerConfiguration: TradingProviderConfiguration {
        TradingProviderConfiguration(
            name: provider, model: modelName.trimmed,
            baseURL: provider.acceptsBaseURL ? providerBaseURL.trimmed.nilIfEmpty : nil
        )
    }

    /// Builds the configuration and secrets to validate; profile builder errors propagate unchanged.
    func submission() throws -> (TradingConfiguration, TradingSecrets) {
        var convertedRoutes: [TradingRouteConfiguration] = []
        var profileByRevision: [String: TradingProfileRevision] = [:]
        for route in routes {
            let profile = try TradingProfileBuilder().build(
                TradingProfileDraft(
                    guruID: route.guruID.trimmed,
                    displayName: route.displayName.trimmed,
                    prefix: route.prefix.trimmed,
                    playbook: route.playbook.trimmedLines,
                    examples: route.examples.map(\.profileExample),
                    exitBasis: route.exitBasis
                ))
            profileByRevision[profile.profileRevision] = profile
            convertedRoutes.append(
                TradingRouteConfiguration(
                    channelID: effectiveChannel(for: route),
                    authorID: route.authorID.trimmed.nilIfEmpty,
                    guruID: profile.guruID,
                    profileRevision: profile.profileRevision,
                    connections: route.connections.map { connection in
                        TradingRouteConnection(
                            accountID: connection.accountID.trimmed,
                            mode: .proportional,
                            amountUSD: amount(for: connection),
                            defaultFraction: connection.useDefaultFraction ? connection.defaultFraction.trimmed : nil
                        )
                    }
                ))
        }
        let configuration = TradingConfiguration(
            source: TradingSourceConfiguration(channelIDs: Self.split(channels), authorIDs: Self.split(authors)),
            provider: providerConfiguration,
            accounts: accounts.map {
                TradingAccountConfiguration(id: $0.name.trimmed, environment: $0.environment, policy: $0.policy)
            },
            profiles: Array(profileByRevision.values).sorted { $0.profileRevision < $1.profileRevision },
            routes: convertedRoutes,
            notification: notificationsEnabled
                ? TradingNotificationConfiguration(service: notificationService, chatID: notificationChatID.trimmed)
                : nil
        )
        let secrets = TradingSecrets(
            discordToken: discordToken,
            providerAPIKey: providerAPIKey,
            brokers: accounts.map {
                TradingBrokerCredentials(accountID: $0.name.trimmed, key: $0.key, secret: $0.secret)
            },
            notificationToken: notificationsEnabled ? notificationToken : nil
        )
        return (configuration, secrets)
    }

    /// The dollars a connection's calls are sized against: its own amount for the same amount
    /// every call, and for a share of the per-stock maximum, that account's current maximum, so
    /// the guru's full position and the account's limit can never disagree.
    func amount(for connection: TradingConnectionDraft) -> String {
        accounts.first { $0.name.trimmed == connection.accountID.trimmed }?.policy.maxSymbolUSD.trimmed ?? ""
    }

    /// Splits on ASCII and full-width commas, so text typed with a Chinese keyboard works too.
    static func split(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension TradingProfileExampleDraft {
    var profileExample: TradingProfileExample {
        TradingProfileExample(
            message: message.trimmedLines,
            expectedAction: expectedAction,
            expectedSymbol: expectedSymbol.trimmed.uppercased(),
            expectedFraction: expectedFraction.trimmed.nilIfEmpty
        )
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
    var trimmedLines: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
