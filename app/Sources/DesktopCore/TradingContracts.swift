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
    public var maxAboveSignalPct = "0"

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
        case maxAboveSignalPct = "max_above_signal_pct"
    }
}

public enum TradingSizingMode: String, Codable, CaseIterable, Sendable {
    case fixed
    case proportional
}

public struct TradingRouteConnection: Codable, Equatable, Identifiable, Sendable {
    public var accountID: String
    public var mode: TradingSizingMode
    public var amountUSD: String
    public var defaultFraction: String?

    public var id: String { accountID }

    public init(
        accountID: String, mode: TradingSizingMode, amountUSD: String,
        defaultFraction: String? = nil
    ) {
        self.accountID = accountID
        self.mode = mode
        self.amountUSD = amountUSD
        self.defaultFraction = defaultFraction
    }

    /// Each entry gets this budget once. The account risk policy caps it afterward.
    public func copiedBudgetUSD(sourceFraction: Decimal?) -> Decimal? {
        guard let amount = Decimal(string: amountUSD), amount > 0 else { return nil }
        let requested: Decimal
        switch mode {
        case .fixed:
            requested = amount
        case .proportional:
            guard let fraction = sourceFraction ?? defaultFraction.flatMap({ Decimal(string: $0) }),
                fraction > 0, fraction <= 1
            else { return nil }
            requested = amount * fraction
        }
        var value = requested
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded > 0 ? rounded : nil
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case mode
        case amountUSD = "amount_usd"
        case defaultFraction = "default_fraction"
    }
}

public struct TradingProfileExample: Codable, Equatable, Sendable {
    public var message: String
    public var expectedAction: TradingInstructionAction
    public var expectedSymbol: String
    public var expectedFraction: String?

    public init(
        message: String, expectedAction: TradingInstructionAction,
        expectedSymbol: String, expectedFraction: String? = nil
    ) {
        self.message = message
        self.expectedAction = expectedAction
        self.expectedSymbol = expectedSymbol
        self.expectedFraction = expectedFraction
    }

    enum CodingKeys: String, CodingKey {
        case message
        case expectedAction = "expected_action"
        case expectedSymbol = "expected_symbol"
        case expectedFraction = "expected_fraction"
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

/// An immutable, content-addressed profile for one guru: a prefix, a playbook, and checked examples.
public struct TradingProfileRevision: Codable, Equatable, Identifiable, Sendable {
    public var guruID: String
    public var displayName: String
    public var prefix: String
    public var playbook: String
    public var examples: [TradingProfileExample]
    public var exitBasis: TradingExitBasis
    public var profileRevision: String

    public var id: String { "\(guruID):\(profileRevision)" }

    public init(
        guruID: String, displayName: String, prefix: String, playbook: String,
        examples: [TradingProfileExample] = [], exitBasis: TradingExitBasis, profileRevision: String
    ) {
        self.guruID = guruID
        self.displayName = displayName
        self.prefix = prefix
        self.playbook = playbook
        self.examples = examples
        self.exitBasis = exitBasis
        self.profileRevision = profileRevision
    }

    enum CodingKeys: String, CodingKey {
        case guruID = "guru_id"
        case displayName = "display_name"
        case prefix
        case playbook
        case examples
        case exitBasis = "exit_basis"
        case profileRevision = "profile_revision"
    }
}

public struct TradingProfileDraft: Equatable, Sendable {
    public var guruID: String
    public var displayName: String
    public var prefix: String
    public var playbook: String
    public var examples: [TradingProfileExample]
    public var exitBasis: TradingExitBasis

    public init(
        guruID: String, displayName: String, prefix: String, playbook: String = "",
        examples: [TradingProfileExample] = [], exitBasis: TradingExitBasis
    ) {
        self.guruID = guruID
        self.displayName = displayName
        self.prefix = prefix
        self.playbook = playbook
        self.examples = examples
        self.exitBasis = exitBasis
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
        [
            try build(
                TradingProfileDraft(
                    guruID: "prepared-standard", displayName: "Standard stock alerts",
                    prefix: "ALERT:", exitBasis: .originalPosition
                )),
            try build(
                TradingProfileDraft(
                    guruID: "prepared-remaining", displayName: "Remaining-position exits",
                    prefix: "TRADE:", exitBasis: .remainingPosition
                )),
        ]
    }

    public func build(_ draft: TradingProfileDraft) throws -> TradingProfileRevision {
        guard
            draft.guruID.range(
                of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression
            ) != nil
        else { throw TradingProfileBuilderError.invalidIdentity }
        guard !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            draft.displayName.count <= 100,
            !draft.prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            draft.prefix.count <= 128,
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
            "prefix": draft.prefix,
            "playbook": draft.playbook,
            "examples": draft.examples.map { example in
                [
                    "message": example.message,
                    "expected_action": example.expectedAction.rawValue,
                    "expected_symbol": example.expectedSymbol,
                    "expected_fraction": example.expectedFraction as Any? ?? NSNull(),
                ] as [String: Any]
            },
            "exit_basis": draft.exitBasis.rawValue,
        ]
        let data = try JSONSerialization.data(withJSONObject: base, options: [.sortedKeys, .withoutEscapingSlashes])
        let revision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return TradingProfileRevision(
            guruID: draft.guruID, displayName: draft.displayName, prefix: draft.prefix,
            playbook: draft.playbook, examples: draft.examples, exitBasis: draft.exitBasis,
            profileRevision: revision
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

    public var id: String { "\(source):\(channelID):\(authorID ?? "*"):\(guruID)" }

    public init(
        source: String = "discord", channelID: String, authorID: String? = nil,
        guruID: String, profileRevision: String, connections: [TradingRouteConnection]
    ) {
        self.source = source
        self.channelID = channelID
        self.authorID = authorID
        self.guruID = guruID
        self.profileRevision = profileRevision
        self.connections = connections
    }

    enum CodingKeys: String, CodingKey {
        case source
        case channelID = "channel_id"
        case authorID = "author_id"
        case guruID = "guru_id"
        case profileRevision = "profile_revision"
        case connections
    }
}

public struct TradingNotificationConfiguration: Codable, Equatable, Sendable {
    public var chatID: String

    public init(chatID: String) { self.chatID = chatID }

    enum CodingKeys: String, CodingKey { case chatID = "chat_id" }
}

/// Saved to application support. This type deliberately contains no credentials.
public struct TradingConfiguration: Codable, Equatable, Sendable {
    /// Matches the engine's CONFIGURATION_VERSION; older saved files are rejected, never migrated.
    public static let currentVersion = 4
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
    case unsupported
}

public enum TradingCapabilityName: String, Codable, Sendable {
    case source
    case model
    case broker
    case notification
    case configuration
    case publicSourceAuthorization = "public_source_authorization"
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
    public var releaseGates: [String]
    public var costNotice: String

    public init(
        configurationRevision: String, activatable: Bool,
        checks: [TradingCapabilityCheck], releaseGates: [String], costNotice: String
    ) {
        self.configurationRevision = configurationRevision
        self.activatable = activatable
        self.checks = checks
        self.releaseGates = releaseGates
        self.costNotice = costNotice
    }

    enum CodingKeys: String, CodingKey {
        case configurationRevision = "configuration_revision"
        case activatable
        case checks
        case releaseGates = "release_gates"
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

/// A draft for the owner to edit: only verbatim, valid example posts survive the engine's checks.
public struct LearnedGuruPlaybook: Codable, Equatable, Sendable {
    public var postsRead: Int
    public var prefix: String?
    public var exitBasis: TradingExitBasis
    public var playbook: String
    public var examples: [TradingProfileExample]
    public var summary: String
    public var provider: String
    public var model: String
    public var costNotice: String

    public init(
        postsRead: Int, prefix: String?, exitBasis: TradingExitBasis, playbook: String,
        examples: [TradingProfileExample], summary: String, provider: String, model: String,
        costNotice: String
    ) {
        self.postsRead = postsRead
        self.prefix = prefix
        self.exitBasis = exitBasis
        self.playbook = playbook
        self.examples = examples
        self.summary = summary
        self.provider = provider
        self.model = model
        self.costNotice = costNotice
    }

    enum CodingKeys: String, CodingKey {
        case postsRead = "posts_read"
        case prefix
        case exitBasis = "exit_basis"
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
    public var exitBasis: TradingExitBasis?
    public var actionEvidence: String
    public var symbolEvidence: String
    public var priceEvidence: String
    public var fractionEvidence: String?

    public init(
        action: TradingInstructionAction, symbol: String, price: String,
        fraction: String?, exitBasis: TradingExitBasis?, actionEvidence: String,
        symbolEvidence: String, priceEvidence: String, fractionEvidence: String?
    ) {
        self.action = action
        self.symbol = symbol
        self.price = price
        self.fraction = fraction
        self.exitBasis = exitBasis
        self.actionEvidence = actionEvidence
        self.symbolEvidence = symbolEvidence
        self.priceEvidence = priceEvidence
        self.fractionEvidence = fractionEvidence
    }

    enum CodingKeys: String, CodingKey {
        case action, symbol, price, fraction
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
    public var exitBasis: TradingExitBasis?
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
        exitBasis: TradingExitBasis?, provider: String, model: String,
        decision: String, reason: String, simulated: Bool, noOrder: Bool,
        costNotice: String, instructions: [ProfileInstructionEvaluation],
        destinations: [ProfileDestinationEvaluation], reviewReasons: [String]
    ) {
        self.messageIdentity = messageIdentity
        self.guruID = guruID
        self.profileRevision = profileRevision
        self.exitBasis = exitBasis
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
        case exitBasis = "exit_basis"
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
