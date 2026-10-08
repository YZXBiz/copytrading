import CryptoKit
import Foundation

public struct TradingSourceConfiguration: Codable, Equatable, Sendable {
    public var channelIDs: [String]
    public var authorIDs: [String]

    public init(channelIDs: [String], authorIDs: [String] = []) {
        self.channelIDs = channelIDs
        self.authorIDs = authorIDs
    }

    enum CodingKeys: String, CodingKey {
        case channelIDs = "channel_ids"
        case authorIDs = "author_ids"
    }
}

/// The services that can read posts, in the order Connections offers them.
public enum TradingProviderName: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openai
    case google
    case deepseek
    case openrouter
    case groq
    case xai
    case mistral
    case together
    case fireworks
    case cerebras
    case moonshotai
    case ollama
    case openAICompatible = "openai_compatible"

    /// A model on the owner's own machine or server may need no key; every hosted service does.
    public var requiresAPIKey: Bool {
        switch self {
        case .ollama, .openAICompatible: false
        default: true
        }
    }

    /// Whether the owner may say where the model is served: required for an OpenAI-compatible
    /// endpoint, an optional override of Ollama's local address, and fixed for the rest.
    public var acceptsBaseURL: Bool { self == .ollama || self == .openAICompatible }

    public var requiresBaseURL: Bool { self == .openAICompatible }
}

public struct TradingProviderConfiguration: Codable, Equatable, Sendable {
    public var name: TradingProviderName
    public var model: String
    /// Where an OpenAI-compatible model is served; nil for services with a fixed address.
    public var baseURL: String?

    public init(name: TradingProviderName, model: String, baseURL: String? = nil) {
        self.name = name
        self.model = model
        self.baseURL = baseURL
    }

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case baseURL = "base_url"
    }

    /// Why this provider's address cannot be used, or nil when it can: an endpoint is required
    /// only where the provider needs one, is allowed only where the owner chooses it, and must be
    /// https, or plain http on this Mac.
    public var baseURLProblem: String? {
        guard let baseURL else {
            return name.requiresBaseURL ? "Enter the base URL your model is served at." : nil
        }
        guard name.acceptsBaseURL else { return "\(name.rawValue) is served at a fixed address." }
        return Self.isAllowedBaseURL(baseURL)
            ? nil : "The base URL must start with https://, or http:// for a model on this Mac."
    }

    /// https anywhere, or http only to this Mac (localhost, 127.0.0.1, or [::1]).
    public static func isAllowedBaseURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty,
            url.user == nil, url.password == nil
        else { return false }
        switch scheme {
        case "https": return true
        case "http": return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        default: return false
        }
    }
}

public struct TradingAccountPolicy: Codable, Equatable, Sendable {
    public var maxOrderUSD = "100"
    public var maxSymbolUSD = "600"
    public var maxTotalUSD = "2500"
    public var dailyLossCapUSD = "250"
    public var maxEntriesPerDay = 30
    public var maxSignalAgeSeconds = 120
    public var orderTimeoutSeconds = 60
    public var pollSeconds = 2.0
    public var extendedHours = true
    public var overnight = false
    public var copyExits = true
    /// Off by default. On, no order is sent by itself: each waits for the owner's Touch ID (ADR-0008).
    public var approveOrders = false
    public var maxAboveSignalPct = "0"
    /// How far below the guru's sell price an exit may fill: every sell is a limit order.
    public var maxBelowSignalPct = "1"

    public init() {}

    enum CodingKeys: String, CodingKey {
        case maxOrderUSD = "max_order_usd"
        case maxSymbolUSD = "max_symbol_usd"
        case maxTotalUSD = "max_total_usd"
        case dailyLossCapUSD = "daily_loss_cap_usd"
        case maxEntriesPerDay = "max_entries_per_day"
        case maxSignalAgeSeconds = "max_signal_age_seconds"
        case orderTimeoutSeconds = "order_timeout_seconds"
        case pollSeconds = "poll_seconds"
        case extendedHours = "extended_hours"
        case overnight
        case copyExits = "copy_exits"
        case approveOrders = "approve_orders"
        case maxAboveSignalPct = "max_above_signal_pct"
        case maxBelowSignalPct = "max_below_signal_pct"
    }
}

/// One guru copying into one account (ADR-0007). The guru's full position is the account's
/// maximum per stock; a call buys its share of it.
public struct TradingRouteConnection: Codable, Equatable, Identifiable, Sendable {
    public var accountID: String
    public var fullPositionUSD: String

    public var id: String { accountID }

    public init(accountID: String, fullPositionUSD: String) {
        self.accountID = accountID
        self.fullPositionUSD = fullPositionUSD
    }

    /// What a call asks for before the account's limits: its share of the full position. The
    /// engine's rule exactly (`requested_entry_budget`): the product's repeating digits settle at
    /// ten places, then it rounds down to the cent, so a third of $3000 is $1000 and six sixths
    /// never pass the full position. `sizing-examples.json` holds both sides to it.
    public func copiedBudgetUSD(sourceFraction: Decimal?) -> Decimal? {
        // A call that names no size asks for the full position (ADR-0010).
        let fraction = sourceFraction ?? 1
        guard let full = Decimal(string: fullPositionUSD), full > 0, fraction > 0, fraction <= 1
        else { return nil }
        var product = full * fraction
        var settled = Decimal()
        NSDecimalRound(&settled, &product, 10, .plain)
        var cents = Decimal()
        NSDecimalRound(&cents, &settled, 2, .down)
        return cents > 0 ? cents : nil
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case fullPositionUSD = "full_position_usd"
    }
}

public struct TradingProfileExample: Codable, Equatable, Sendable {
    public var message: String
    public var expectedAction: TradingInstructionAction
    public var expectedSymbol: String
    public var expectedFraction: String?
    /// The guru's price in the post, and for a sell the buy price it names (ADR-0010).
    public var expectedPrice: String?
    public var expectedBuyPrice: String?

    public init(
        message: String, expectedAction: TradingInstructionAction,
        expectedSymbol: String, expectedFraction: String? = nil,
        expectedPrice: String? = nil, expectedBuyPrice: String? = nil
    ) {
        self.message = message
        self.expectedAction = expectedAction
        self.expectedSymbol = expectedSymbol
        self.expectedFraction = expectedFraction
        self.expectedPrice = expectedPrice
        self.expectedBuyPrice = expectedBuyPrice
    }

    enum CodingKeys: String, CodingKey {
        case message
        case expectedAction = "expected_action"
        case expectedSymbol = "expected_symbol"
        case expectedFraction = "expected_fraction"
        case expectedPrice = "expected_price"
        case expectedBuyPrice = "expected_buy_price"
    }
}

public enum TradingInstructionAction: String, Codable, CaseIterable, Sendable {
    case buy
    case reduce
    case close
}

public enum TradingExitBasis: String, Codable, CaseIterable, Sendable {
    case originalPosition = "original_position"
    case remainingPosition = "remaining_position"
}

/// The longest playbook the engine accepts.
public let tradingPlaybookMaxLength = 8_000

public struct TradingProfileRevision: Codable, Equatable, Identifiable, Sendable {
    public var guruID: String
    public var displayName: String
    public var playbook: String
    public var examples: [TradingProfileExample]
    public var profileRevision: String

    public var id: String { "\(guruID):\(profileRevision)" }

    public init(
        guruID: String, displayName: String, playbook: String,
        examples: [TradingProfileExample] = [], profileRevision: String
    ) {
        self.guruID = guruID
        self.displayName = displayName
        self.playbook = playbook
        self.examples = examples
        self.profileRevision = profileRevision
    }

    enum CodingKeys: String, CodingKey {
        case guruID = "guru_id"
        case displayName = "display_name"
        case playbook
        case examples
        case profileRevision = "profile_revision"
    }
}

public struct TradingProfileDraft: Equatable, Sendable {
    public var guruID: String
    public var displayName: String
    public var playbook: String
    public var examples: [TradingProfileExample]

    public init(
        guruID: String, displayName: String, playbook: String = "",
        examples: [TradingProfileExample] = []
    ) {
        self.guruID = guruID
        self.displayName = displayName
        self.playbook = playbook
        self.examples = examples
    }
}

public enum TradingProfileBuilderError: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidProfile
    case invalidExample
}

/// Builds profile revisions whose hash matches the engine's (sorted-key JSON, SHA-256).
public struct TradingProfileBuilder: Sendable {
    public init() {}

    public func preparedProfiles() throws -> [TradingProfileRevision] {
        [try build(TradingProfileDraft(guruID: "prepared-standard", displayName: "Standard stock alerts"))]
    }

    public func build(_ draft: TradingProfileDraft) throws -> TradingProfileRevision {
        guard
            draft.guruID.range(
                of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression
            ) != nil
        else { throw TradingProfileBuilderError.invalidIdentity }
        guard !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            draft.displayName.count <= 100,
            draft.playbook.count <= tradingPlaybookMaxLength,
            draft.examples.count <= 32
        else { throw TradingProfileBuilderError.invalidProfile }
        for example in draft.examples {
            guard !example.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                example.message.count <= 2_000,
                example.expectedSymbol.range(
                    of: "^[A-Z]{1,5}(?:[.][A-Z])?$", options: .regularExpression
                ) != nil
            else { throw TradingProfileBuilderError.invalidExample }
            for price in [example.expectedPrice, example.expectedBuyPrice].compactMap({ $0 }) {
                guard let value = Decimal(string: price), value > 0, value <= 100_000 else {
                    throw TradingProfileBuilderError.invalidExample
                }
            }
            if example.expectedAction == .buy, example.expectedBuyPrice != nil {
                throw TradingProfileBuilderError.invalidExample
            }
            if let rawFraction = example.expectedFraction {
                guard let value = Decimal(string: rawFraction), value > 0, value <= 1 else {
                    throw TradingProfileBuilderError.invalidExample
                }
            }
            if example.expectedAction != .buy {
                guard let fraction = example.expectedFraction,
                    let value = Decimal(string: fraction), value > 0, value <= 1,
                    !(example.expectedAction == .close && value != 1),
                    !(example.expectedAction == .reduce && value == 1)
                else {
                    throw TradingProfileBuilderError.invalidExample
                }
            }
        }

        let base: [String: Any] = [
            "guru_id": draft.guruID,
            "display_name": draft.displayName,
            "playbook": draft.playbook,
            "examples": draft.examples.map { example in
                [
                    "message": example.message,
                    "expected_action": example.expectedAction.rawValue,
                    "expected_symbol": example.expectedSymbol,
                    "expected_fraction": example.expectedFraction as Any? ?? NSNull(),
                    "expected_price": example.expectedPrice as Any? ?? NSNull(),
                    "expected_buy_price": example.expectedBuyPrice as Any? ?? NSNull(),
                ] as [String: Any]
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: base, options: [.sortedKeys, .withoutEscapingSlashes])
        let revision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return TradingProfileRevision(
            guruID: draft.guruID, displayName: draft.displayName,
            playbook: draft.playbook, examples: draft.examples, profileRevision: revision
        )
    }
}

public enum TradingEnvironment: String, Codable, CaseIterable, Sendable {
    case paper
    case live
}

public struct TradingAccountConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var environment: TradingEnvironment
    public var policy: TradingAccountPolicy

    public init(id: String, environment: TradingEnvironment, policy: TradingAccountPolicy = .init()) {
        self.id = id
        self.environment = environment
        self.policy = policy
    }
}

public struct TradingRouteConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var source: String
    public var channelID: String
    public var authorID: String?
    public var guruID: String
    public var profileRevision: String
    public var connections: [TradingRouteConnection]
    /// The same call again within this many minutes is the guru re-posting it; nil copies every
    /// post. A saved route without the key checks ten minutes, as the engine does.
    public var repeatWindowMinutes: Int?

    public static let defaultRepeatWindowMinutes = 10
    public static let repeatWindowRange = 1...1440

    public var id: String { "\(source):\(channelID):\(authorID ?? "*"):\(guruID)" }

    public init(
        source: String = "discord", channelID: String, authorID: String? = nil,
        guruID: String, profileRevision: String, connections: [TradingRouteConnection],
        repeatWindowMinutes: Int? = TradingRouteConfiguration.defaultRepeatWindowMinutes
    ) {
        self.source = source
        self.channelID = channelID
        self.authorID = authorID
        self.guruID = guruID
        self.profileRevision = profileRevision
        self.connections = connections
        self.repeatWindowMinutes = repeatWindowMinutes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        channelID = try container.decode(String.self, forKey: .channelID)
        authorID = try container.decodeIfPresent(String.self, forKey: .authorID)
        guruID = try container.decode(String.self, forKey: .guruID)
        profileRevision = try container.decode(String.self, forKey: .profileRevision)
        connections = try container.decode([TradingRouteConnection].self, forKey: .connections)
        // An absent key is the default; an explicit null is the owner turning the check off.
        repeatWindowMinutes =
            container.contains(.repeatWindowMinutes)
            ? try container.decodeIfPresent(Int.self, forKey: .repeatWindowMinutes)
            : Self.defaultRepeatWindowMinutes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(channelID, forKey: .channelID)
        try container.encodeIfPresent(authorID, forKey: .authorID)
        try container.encode(guruID, forKey: .guruID)
        try container.encode(profileRevision, forKey: .profileRevision)
        try container.encode(connections, forKey: .connections)
        // Always written, null when off: leaving it out would mean the default.
        try container.encode(repeatWindowMinutes, forKey: .repeatWindowMinutes)
    }

    enum CodingKeys: String, CodingKey {
        case source
        case channelID = "channel_id"
        case authorID = "author_id"
        case guruID = "guru_id"
        case profileRevision = "profile_revision"
        case connections
        case repeatWindowMinutes = "repeat_window_minutes"
    }
}

/// Where alerts go.
public enum TradingAlertService: String, Codable, CaseIterable, Sendable {
    case telegram
    case discord
}

/// Telegram names a chat; a Discord webhook already names its channel, and its URL is the secret.
public struct TradingNotificationConfiguration: Codable, Equatable, Sendable {
    public var service: TradingAlertService
    public var chatID: String?

    public init(service: TradingAlertService = .telegram, chatID: String?) {
        self.service = service
        self.chatID = service == .telegram ? chatID : nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        service = try container.decodeIfPresent(TradingAlertService.self, forKey: .service) ?? .telegram
        chatID = try container.decodeIfPresent(String.self, forKey: .chatID)
    }

    enum CodingKeys: String, CodingKey {
        case service
        case chatID = "chat_id"
    }
}

/// Saved to application support. This type deliberately contains no credentials.
public struct TradingConfiguration: Codable, Equatable, Sendable {
    /// Matches the engine's CONFIGURATION_VERSION; older saved files are rejected, never migrated.
    public static let currentVersion = 8
    public var version = TradingConfiguration.currentVersion
    public var source: TradingSourceConfiguration
    public var provider: TradingProviderConfiguration
    public var accounts: [TradingAccountConfiguration]
    public var profiles: [TradingProfileRevision]
    public var routes: [TradingRouteConfiguration]
    public var notification: TradingNotificationConfiguration?

    public init(
        source: TradingSourceConfiguration,
        provider: TradingProviderConfiguration,
        accounts: [TradingAccountConfiguration],
        profiles: [TradingProfileRevision],
        routes: [TradingRouteConfiguration],
        notification: TradingNotificationConfiguration? = nil
    ) {
        self.source = source
        self.provider = provider
        self.accounts = accounts
        self.profiles = profiles
        self.routes = routes
        self.notification = notification
    }

    enum CodingKeys: String, CodingKey {
        case version
        case source
        case provider
        case accounts
        case profiles
        case routes
        case notification
    }
}

public struct TradingBrokerCredentials: Codable, Equatable, Sendable {
    public var accountID: String
    public var key: String
    public var secret: String

    public init(accountID: String, key: String, secret: String) {
        self.accountID = accountID
        self.key = key
        self.secret = secret
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case key, secret
    }
}

/// One service checked the moment the owner connects it, with the keys typed for it. The engine
/// runs the same read-only check a full validation runs for it, and saves nothing.
public enum TradingConnectionCheck: Encodable, Equatable, Sendable {
    case source(TradingSourceConfiguration, token: String)
    case model(TradingProviderConfiguration, apiKey: String)
    case broker(TradingAccountConfiguration, credentials: TradingBrokerCredentials)
    case notification(TradingNotificationConfiguration, token: String)

    enum CodingKeys: String, CodingKey {
        case kind, source, token, provider, account, credentials, notification
        case apiKey = "api_key"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .source(let source, let token):
            try container.encode("source", forKey: .kind)
            try container.encode(source, forKey: .source)
            try container.encode(token, forKey: .token)
        case .model(let provider, let apiKey):
            try container.encode("model", forKey: .kind)
            try container.encode(provider, forKey: .provider)
            try container.encode(apiKey, forKey: .apiKey)
        case .broker(let account, let credentials):
            try container.encode("broker", forKey: .kind)
            try container.encode(account, forKey: .account)
            try container.encode(credentials, forKey: .credentials)
        case .notification(let notification, let token):
            try container.encode("notification", forKey: .kind)
            try container.encode(notification, forKey: .notification)
            try container.encode(token, forKey: .token)
        }
    }
}

/// Keychain only. Sent over the private child pipe after an explicit Start action.
public struct TradingSecrets: Codable, Equatable, Sendable {
    public var discordToken: String
    public var providerAPIKey: String
    public var brokers: [TradingBrokerCredentials]
    public var notificationToken: String?

    public init(
        discordToken: String,
        providerAPIKey: String,
        brokers: [TradingBrokerCredentials],
        notificationToken: String? = nil
    ) {
        self.discordToken = discordToken
        self.providerAPIKey = providerAPIKey
        self.brokers = brokers
        self.notificationToken = notificationToken
    }

    enum CodingKeys: String, CodingKey {
        case discordToken = "discord_token"
        case providerAPIKey = "provider_api_key"
        case brokers
        case notificationToken = "notification_token"
    }
}

public enum TradingRunState: String, Codable, Equatable, Sendable {
    case paused
    case starting
    case running
    case degraded
    case pausing
    case failed
}

public struct TradingAccountStatus: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let state: String
    public let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case errorCode = "error_code"
    }
}

public struct TradingStatus: Codable, Equatable, Sendable {
    public let state: TradingRunState
    public let configuredAccounts: Int
    public let activeAccounts: Int
    public let sourceConnected: Bool
    public let modelReady: Bool
    public let pendingSource: Int
    public let oldestPendingSourceAt: String?
    public let pendingSignals: Int
    public let oldestPendingSignalAt: String?
    public let processedSignals: Int
    public let errorCode: String?
    public let accounts: [TradingAccountStatus]

    enum CodingKeys: String, CodingKey {
        case state
        case configuredAccounts = "configured_accounts"
        case activeAccounts = "active_accounts"
        case sourceConnected = "source_connected"
        case modelReady = "model_ready"
        case pendingSource = "pending_source"
        case oldestPendingSourceAt = "oldest_pending_source_at"
        case pendingSignals = "pending_signals"
        case oldestPendingSignalAt = "oldest_pending_signal_at"
        case processedSignals = "processed_signals"
        case errorCode = "error_code"
        case accounts
    }
}

public enum TradingActivationPhase: String, Codable, Equatable, Sendable {
    case notFound = "not_found"
    case starting
    case ready
    case failed
    case stopped
    case interrupted
}

public struct TradingActivationStatus: Codable, Equatable, Sendable {
    public let requestedActivationID: String
    public let activationID: String?
    public let candidateRevision: String?
    public let committedRevision: String?
    public let committedActivationID: String?
    public let phase: TradingActivationPhase
    public let runtimeState: TradingRunState
    public let errorCode: String?

    public init(
        requestedActivationID: String,
        activationID: String?,
        candidateRevision: String?,
        committedRevision: String?,
        phase: TradingActivationPhase,
        runtimeState: TradingRunState,
        errorCode: String?,
        committedActivationID: String? = nil
    ) {
        self.requestedActivationID = requestedActivationID
        self.activationID = activationID
        self.candidateRevision = candidateRevision
        self.committedRevision = committedRevision
        self.committedActivationID = committedActivationID
        self.phase = phase
        self.runtimeState = runtimeState
        self.errorCode = errorCode
    }

    enum CodingKeys: String, CodingKey {
        case requestedActivationID = "requested_activation_id"
        case activationID = "activation_id"
        case candidateRevision = "candidate_revision"
        case committedRevision = "committed_revision"
        case committedActivationID = "committed_activation_id"
        case phase
        case runtimeState = "runtime_state"
        case errorCode = "error_code"
    }
}

public enum TradingCapabilityState: String, Codable, Sendable {
    case ready
    case failed
    case notConfigured = "not_configured"
}

public enum TradingCapabilityName: String, Codable, Sendable {
    case source
    case model
    case broker
    case notification
    case configuration
}

/// Safe capability evidence. Engine responses never contain submitted credentials or raw errors.
public struct TradingCapabilityCheck: Codable, Equatable, Identifiable, Sendable {
    public var name: TradingCapabilityName
    public var state: TradingCapabilityState
    public var subject: String?
    public var environment: TradingEnvironment?
    public var identity: String?
    public var adapter: String
    public var reasonCode: String?
    /// A close model name the provider lists, when the one asked for does not exist.
    public var suggestion: String?

    public var id: String { "\(name.rawValue):\(subject ?? ""):\(adapter)" }

    public init(
        name: TradingCapabilityName, state: TradingCapabilityState, subject: String? = nil,
        environment: TradingEnvironment? = nil, identity: String? = nil,
        adapter: String, reasonCode: String? = nil, suggestion: String? = nil
    ) {
        self.name = name
        self.state = state
        self.subject = subject
        self.environment = environment
        self.identity = identity
        self.adapter = adapter
        self.reasonCode = reasonCode
        self.suggestion = suggestion
    }

    enum CodingKeys: String, CodingKey {
        case name
        case state
        case subject
        case environment
        case identity
        case adapter
        case reasonCode = "reason_code"
        case suggestion
    }
}

public struct TradingCapabilityReport: Codable, Equatable, Sendable {
    public var configurationRevision: String
    public var activatable: Bool
    public var checks: [TradingCapabilityCheck]
    public var costNotice: String

    public init(
        configurationRevision: String, activatable: Bool,
        checks: [TradingCapabilityCheck], costNotice: String
    ) {
        self.configurationRevision = configurationRevision
        self.activatable = activatable
        self.checks = checks
        self.costNotice = costNotice
    }

    enum CodingKeys: String, CodingKey {
        case configurationRevision = "configuration_revision"
        case activatable
        case checks
        case costNotice = "cost_notice"
    }
}

public struct TradingValidation: Codable, Equatable, Sendable {
    public var report: TradingCapabilityReport
    public var activationToken: String?

    public init(report: TradingCapabilityReport, activationToken: String?) {
        self.report = report
        self.activationToken = activationToken
    }

    enum CodingKeys: String, CodingKey {
        case report
        case activationToken = "activation_token"
    }
}

/// Transient engine request. The API key is sent only over the private pipe and never saved here.
public struct HistoricalProfileEvaluationRequest: Codable, Equatable, Sendable {
    public var sourceID: String
    public var profile: TradingProfileRevision
    public var provider: TradingProviderConfiguration
    public var providerAPIKey: String
    public var destinations: [TradingRouteConnection]

    public init(
        sourceID: String, profile: TradingProfileRevision,
        provider: TradingProviderConfiguration, providerAPIKey: String,
        destinations: [TradingRouteConnection]
    ) {
        self.sourceID = sourceID
        self.profile = profile
        self.provider = provider
        self.providerAPIKey = providerAPIKey
        self.destinations = destinations
    }

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case profile
        case provider
        case providerAPIKey = "provider_api_key"
        case destinations
    }
}

/// Transient draft-only operation. The provider secret is sent over private IPC and is not stored.
/// Ask the engine to read a channel's recent posts and draft a playbook. Nothing is saved.
public struct GuruPlaybookLearningRequest: Equatable, Sendable {
    public var channelID: String
    public var authorID: String?
    public var discordToken: String
    public var provider: TradingProviderConfiguration
    public var providerAPIKey: String

    public init(
        channelID: String, authorID: String?, discordToken: String,
        provider: TradingProviderConfiguration, providerAPIKey: String
    ) {
        self.channelID = channelID
        self.authorID = authorID
        self.discordToken = discordToken
        self.provider = provider
        self.providerAPIKey = providerAPIKey
    }
}

/// Read a guru's recent posts with a draft profile before switching them on (ADR-0007).
public struct GuruReplayRequest: Equatable, Sendable {
    public var channelID: String
    public var authorID: String?
    public var discordToken: String
    public var provider: TradingProviderConfiguration
    public var providerAPIKey: String
    public var profile: TradingProfileRevision
    /// The guru's accounts, so each replayed buy says how much it would spend.
    public var destinations: [TradingRouteConnection]

    public init(
        channelID: String, authorID: String?, discordToken: String,
        provider: TradingProviderConfiguration, providerAPIKey: String, profile: TradingProfileRevision,
        destinations: [TradingRouteConnection]
    ) {
        self.channelID = channelID
        self.authorID = authorID
        self.discordToken = discordToken
        self.provider = provider
        self.providerAPIKey = providerAPIKey
        self.profile = profile
        self.destinations = destinations
    }
}

/// What one recent post would have done under a draft; nothing was placed.
public struct ReplayedPost: Codable, Equatable, Sendable {
    public let text: String
    public let decision: String
    public let reason: String
    public let reading: PostReading?
    public let instructions: [SourceInstruction]
    public let suggested: [SourceInstruction]
    /// What each of the guru's accounts would spend, before the account's maximum per order.
    public let destinations: [ProfileDestinationEvaluation]
}

public struct GuruReplay: Codable, Equatable, Sendable {
    public let posts: [ReplayedPost]
    public let provider: String
    public let model: String
    public let costNotice: String

    public init(posts: [ReplayedPost], provider: String, model: String, costNotice: String) {
        self.posts = posts
        self.provider = provider
        self.model = model
        self.costNotice = costNotice
    }

    enum CodingKeys: String, CodingKey {
        case posts, provider, model
        case costNotice = "cost_notice"
    }
}

/// A draft for the owner to edit: only verbatim, valid example posts survive the engine's checks.
public struct LearnedGuruPlaybook: Codable, Equatable, Sendable {
    public var postsRead: Int
    public var playbook: String
    public var examples: [TradingProfileExample]
    public var summary: String
    public var provider: String
    public var model: String
    public var costNotice: String

    public init(
        postsRead: Int, playbook: String,
        examples: [TradingProfileExample], summary: String, provider: String, model: String,
        costNotice: String
    ) {
        self.postsRead = postsRead
        self.playbook = playbook
        self.examples = examples
        self.summary = summary
        self.provider = provider
        self.model = model
        self.costNotice = costNotice
    }

    enum CodingKeys: String, CodingKey {
        case postsRead = "posts_read"
        case playbook, examples, summary, provider, model
        case costNotice = "cost_notice"
    }
}

public struct ProfileExampleReviewRequest: Codable, Equatable, Sendable {
    public var profile: TradingProfileRevision
    public var provider: TradingProviderConfiguration
    public var providerAPIKey: String
    public var destinations: [TradingRouteConnection]

    public init(
        profile: TradingProfileRevision, provider: TradingProviderConfiguration,
        providerAPIKey: String, destinations: [TradingRouteConnection]
    ) {
        self.profile = profile
        self.provider = provider
        self.providerAPIKey = providerAPIKey
        self.destinations = destinations
    }

    enum CodingKeys: String, CodingKey {
        case profile, provider, destinations
        case providerAPIKey = "provider_api_key"
    }
}

public struct ProfileInstructionEvaluation: Codable, Equatable, Sendable {
    public var action: TradingInstructionAction
    public var symbol: String
    public var price: String
    public var fraction: String?
    /// For a sell, the buy price it names; nil when it sells from every buy.
    public var entryPrice: String?
    public var exitBasis: TradingExitBasis?
    public var actionEvidence: String
    public var symbolEvidence: String
    public var priceEvidence: String
    public var fractionEvidence: String?

    public init(
        action: TradingInstructionAction, symbol: String, price: String,
        fraction: String?, entryPrice: String? = nil, exitBasis: TradingExitBasis?, actionEvidence: String,
        symbolEvidence: String, priceEvidence: String, fractionEvidence: String?
    ) {
        self.action = action
        self.symbol = symbol
        self.price = price
        self.fraction = fraction
        self.entryPrice = entryPrice
        self.exitBasis = exitBasis
        self.actionEvidence = actionEvidence
        self.symbolEvidence = symbolEvidence
        self.priceEvidence = priceEvidence
        self.fractionEvidence = fractionEvidence
    }

    enum CodingKeys: String, CodingKey {
        case action, symbol, price, fraction
        case entryPrice = "entry_price"
        case exitBasis = "exit_basis"
        case actionEvidence = "action_evidence"
        case symbolEvidence = "symbol_evidence"
        case priceEvidence = "price_evidence"
        case fractionEvidence = "fraction_evidence"
    }
}

public struct ProfileDestinationEvaluation: Codable, Equatable, Sendable {
    public var accountID: String
    public var action: TradingInstructionAction
    public var symbol: String
    public var budgetUSD: String?
    public var estimatedQuantity: String?
    public var exitBasis: TradingExitBasis?
    public var reason: String

    public init(
        accountID: String, action: TradingInstructionAction, symbol: String,
        budgetUSD: String?, estimatedQuantity: String?, exitBasis: TradingExitBasis?,
        reason: String
    ) {
        self.accountID = accountID
        self.action = action
        self.symbol = symbol
        self.budgetUSD = budgetUSD
        self.estimatedQuantity = estimatedQuantity
        self.exitBasis = exitBasis
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case action, symbol
        case budgetUSD = "budget_usd"
        case estimatedQuantity = "estimated_quantity"
        case exitBasis = "exit_basis"
        case reason
    }
}

public struct ProfileEvaluation: Codable, Equatable, Sendable {
    public var messageIdentity: String
    public var guruID: String
    public var profileRevision: String
    public var provider: String
    public var model: String
    public var decision: String
    public var reason: String
    public var simulated: Bool
    public var noOrder: Bool
    public var costNotice: String
    public var instructions: [ProfileInstructionEvaluation]
    public var destinations: [ProfileDestinationEvaluation]
    public var reviewReasons: [String]

    public init(
        messageIdentity: String, guruID: String, profileRevision: String,
        provider: String, model: String,
        decision: String, reason: String, simulated: Bool, noOrder: Bool,
        costNotice: String, instructions: [ProfileInstructionEvaluation],
        destinations: [ProfileDestinationEvaluation], reviewReasons: [String]
    ) {
        self.messageIdentity = messageIdentity
        self.guruID = guruID
        self.profileRevision = profileRevision
        self.provider = provider
        self.model = model
        self.decision = decision
        self.reason = reason
        self.simulated = simulated
        self.noOrder = noOrder
        self.costNotice = costNotice
        self.instructions = instructions
        self.destinations = destinations
        self.reviewReasons = reviewReasons
    }

    enum CodingKeys: String, CodingKey {
        case messageIdentity = "message_identity"
        case guruID = "guru_id"
        case profileRevision = "profile_revision"
        case provider, model, decision, reason, simulated
        case noOrder = "no_order"
        case costNotice = "cost_notice"
        case instructions, destinations
        case reviewReasons = "review_reasons"
    }
}

public struct ProfileExampleComparison: Codable, Equatable, Sendable {
    public var exampleIndex: Int
    public var expectedAction: TradingInstructionAction
    public var expectedSymbol: String
    public var expectedFraction: String?
    public var actual: ProfileEvaluation
    public var matches: Bool
    public var reviewReasons: [String]

    public init(
        exampleIndex: Int, expectedAction: TradingInstructionAction,
        expectedSymbol: String, expectedFraction: String?, actual: ProfileEvaluation,
        matches: Bool, reviewReasons: [String]
    ) {
        self.exampleIndex = exampleIndex
        self.expectedAction = expectedAction
        self.expectedSymbol = expectedSymbol
        self.expectedFraction = expectedFraction
        self.actual = actual
        self.matches = matches
        self.reviewReasons = reviewReasons
    }

    enum CodingKeys: String, CodingKey {
        case exampleIndex = "example_index"
        case expectedAction = "expected_action"
        case expectedSymbol = "expected_symbol"
        case expectedFraction = "expected_fraction"
        case actual, matches
        case reviewReasons = "review_reasons"
    }
}

public struct ProfileExampleReview: Codable, Equatable, Sendable {
    public var guruID: String
    public var profileRevision: String
    public var provider: String
    public var model: String
    public var simulated: Bool
    public var noOrder: Bool
    public var costNotice: String
    public var examples: [ProfileExampleComparison]
    public var reviewReasons: [String]
    public var automaticActivationAllowed: Bool

    public init(
        guruID: String, profileRevision: String,
        provider: String, model: String, simulated: Bool = true, noOrder: Bool = true,
        costNotice: String, examples: [ProfileExampleComparison],
        reviewReasons: [String] = [], automaticActivationAllowed: Bool
    ) {
        self.guruID = guruID
        self.profileRevision = profileRevision
        self.provider = provider
        self.model = model
        self.simulated = simulated
        self.noOrder = noOrder
        self.costNotice = costNotice
        self.examples = examples
        self.reviewReasons = reviewReasons
        self.automaticActivationAllowed = automaticActivationAllowed
    }

    enum CodingKeys: String, CodingKey {
        case guruID = "guru_id"
        case profileRevision = "profile_revision"
        case provider, model, simulated
        case noOrder = "no_order"
        case costNotice = "cost_notice"
        case examples
        case reviewReasons = "review_reasons"
        case automaticActivationAllowed = "automatic_activation_allowed"
    }
}
