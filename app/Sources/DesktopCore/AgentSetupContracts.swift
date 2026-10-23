import Foundation

/// The setup operations of the `copytrading` contract that the app answers itself. Their keys go
/// to the Keychain, so these lines never reach the engine; it only decides whether they may run.
public enum AgentSetupOperation: String, CaseIterable, Codable, Equatable, Sendable {
    case show = "get_setup"
    case discord = "edit_setup_discord"
    case model = "edit_setup_model"
    case account = "edit_setup_account"
    case guru = "edit_setup_guru"
    case alerts = "edit_setup_alerts"
    case importSetup = "import_setup"
    case apply = "apply_setup"
    case discard = "discard_setup"

    /// The setup operation a request line names; nil for every other line, valid or not.
    public static func of(line: String) -> AgentSetupOperation? {
        struct Peek: Decodable { let operation: String? }
        guard let peek = try? JSONDecoder().decode(Peek.self, from: Data(line.utf8)) else { return nil }
        return peek.operation.flatMap(AgentSetupOperation.init(rawValue:))
    }
}

/// A key, token or secret from an agent request. It prints as dots, so no log, error, or
/// description can show it; only `value` reads it, for the draft and then the Keychain.
public struct AgentSecret: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let value: String

    public init(_ value: String) { self.value = value }

    public var description: String { "••••" }
    public var debugDescription: String { "••••" }
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// Why a setup request line was refused before anything ran; the message names fields, never values.
public struct AgentSetupRequestError: Error, Equatable, Sendable {
    public let requestID: String
    public let message: String
}

/// One `copytrading setup …` request, decoded and checked the way the contract's models check it.
public struct AgentSetupRequest: Equatable, Sendable {
    public enum Action: String, Decodable, Equatable, Sendable {
        case add
        case edit
        case remove
    }

    public struct Discord: Equatable, Sendable {
        public var channelIDs: [String]?
        /// Empty copies every author in the channels.
        public var authorIDs: [String]?
        public var token: AgentSecret?
    }

    public struct Model: Equatable, Sendable {
        public var service: TradingProviderName?
        public var model: String?
        /// Empty clears it.
        public var baseURL: String?
        public var key: AgentSecret?
    }

    public struct Account: Equatable, Sendable {
        public var action: Action
        public var accountID: String
        public var rename: String?
        public var environment: TradingEnvironment?
        public var key: AgentSecret?
        public var secret: AgentSecret?
        public var limits: [AgentLimitChange]
        /// What the account does after a restart: Wait for me (manual) or Carry on by itself.
        public var recoveryPreference: RecoveryPreference?
    }

    public struct Guru: Equatable, Sendable {
        public var action: Action
        /// The guru's name or ID; for add, the new guru's name.
        public var guru: String
        public var rename: String?
        /// Empty follows the first source channel.
        public var channelID: String?
        /// Empty copies every author in the channel.
        public var authorID: String?
        public var accountID: String?
        /// The guru's own full position in their account: a 1/6 call buys a sixth of it.
        public var fullPositionUSD: String?
        public var playbook: String?
        /// 0 copies every post.
        public var repeatWindowMinutes: Int?
    }

    public struct Alerts: Equatable, Sendable {
        public var enabled: Bool?
        public var service: TradingAlertService?
        public var chatID: String?
        public var token: AgentSecret?
    }

    public enum Edit: Equatable, Sendable {
        case show
        case discord(Discord)
        case model(Model)
        case account(Account)
        case guru(Guru)
        case alerts(Alerts)
        case importText(AgentSecret)
        /// `start`: also start copying that is paused or never started.
        case apply(start: Bool)
        case discard
    }

    public static let limitFields: Set<String> = [
        "max_order_usd", "max_symbol_usd", "max_total_usd", "daily_loss_cap_usd", "max_entries_per_day",
        "max_signal_age_seconds", "order_timeout_seconds", "poll_seconds", "extended_hours", "overnight",
        "copy_exits", "approve_orders", "max_above_signal_pct", "max_below_signal_pct",
    ]
    public static let importMaximumCharacters = 60_000
    public static let maximumRepeatWindowMinutes = 1440

    public let requestID: String
    public let operation: AgentSetupOperation
    public let edit: Edit

    /// Decodes one request line; a line that breaks the contract throws with what to fix.
    public init(line: String) throws(AgentSetupRequestError) {
        let data = Data(line.utf8)
        let header = (try? JSONDecoder().decode(Header.self, from: data))
        let requestID = header?.requestID.flatMap { (1...128).contains($0.count) ? $0 : nil } ?? ""
        func fail(_ message: String) -> AgentSetupRequestError {
            AgentSetupRequestError(requestID: requestID, message: message)
        }
        guard let header, header.schemaVersion == 1, !requestID.isEmpty,
            let operation = header.operation.flatMap(AgentSetupOperation.init(rawValue:))
        else { throw fail("The request is not a setup request this CopyTrading understands.") }
        let body: Body
        do {
            body = try JSONDecoder().decode(Body.self, from: data)
        } catch {
            throw fail("The \(operation.rawValue) request is not valid: \(Self.field(of: error)).")
        }
        self.requestID = requestID
        self.operation = operation
        do {
            edit = try Self.edit(operation, body)
        } catch let problem as Problem {
            throw fail(problem.message)
        } catch {
            throw fail("The \(operation.rawValue) request is not valid.")
        }
    }

    private struct Problem: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private static func field(of error: any Error) -> String {
        guard let error = error as? DecodingError else { return "it is not JSON" }
        let path: [any CodingKey]
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            path = context.codingPath
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
        @unknown default:
            path = []
        }
        let name = path.map(\.stringValue).joined(separator: ".")
        return name.isEmpty ? "it is not JSON" : "check \(name)"
    }

    private static func edit(_ operation: AgentSetupOperation, _ body: Body) throws -> Edit {
        switch operation {
        case .show: return .show
        case .apply: return .apply(start: body.start ?? false)
        case .discard: return .discard
        case .discord:
            let edit = Discord(
                channelIDs: try body.channelIDs.map { try discordIDs($0, field: "channel_ids", atLeastOne: true) },
                authorIDs: try body.authorIDs.map { try discordIDs($0, field: "author_ids", atLeastOne: false) },
                token: try secret(body.token, field: "token"))
            guard edit.channelIDs != nil || edit.authorIDs != nil || edit.token != nil else {
                throw Problem("Name at least one thing to change.")
            }
            return .discord(edit)
        case .model:
            var service: TradingProviderName?
            if let name = body.service {
                guard let known = TradingProviderName(rawValue: name) else {
                    throw Problem("There is no model service called \(quoted(name)).")
                }
                service = known
            }
            if let model = body.model, !(1...200).contains(model.count) {
                throw Problem("A model name is 1 to 200 characters.")
            }
            if let url = body.baseURL, url.count > 2048 { throw Problem("The base URL is too long.") }
            let edit = Model(
                service: service, model: body.model, baseURL: body.baseURL, key: try secret(body.key, field: "key"))
            guard edit.service != nil || edit.model != nil || edit.baseURL != nil || edit.key != nil else {
                throw Problem("Name at least one thing to change.")
            }
            return .model(edit)
        case .account:
            guard let action = body.action else { throw Problem("Say add, edit, or remove.") }
            let accountID = try accountName(body.accountID, field: "account_id")
            let edit = Account(
                action: action, accountID: accountID,
                rename: try body.rename.map { try accountName($0, field: "rename") },
                environment: try body.environment.map {
                    guard let environment = TradingEnvironment(rawValue: $0) else {
                        throw Problem("An account is paper or live.")
                    }
                    return environment
                },
                key: try secret(body.key, field: "key"), secret: try secret(body.secret, field: "secret"),
                limits: body.limits ?? [],
                recoveryPreference: try body.recoveryPreference.map {
                    guard let preference = RecoveryPreference(rawValue: $0) else {
                        throw Problem("After a restart an account waits (manual) or carries on (automatic).")
                    }
                    return preference
                })
            guard (edit.key == nil) == (edit.secret == nil) else {
                throw Problem("Give the Alpaca key and its secret together.")
            }
            for change in edit.limits where !limitFields.contains(change.field) {
                throw Problem("\(quoted(change.field)) is not an account setting.")
            }
            guard Set(edit.limits.map(\.field)).count == edit.limits.count else {
                throw Problem("A setting is named twice.")
            }
            let changes =
                edit.rename != nil || edit.environment != nil || edit.key != nil || !edit.limits.isEmpty
                || edit.recoveryPreference != nil
            switch action {
            case .remove where changes: throw Problem("Removing an account takes only its name.")
            case .add where edit.rename != nil: throw Problem("A new account is named once.")
            case .edit where !changes: throw Problem("Name at least one thing to change.")
            default: return .account(edit)
            }
        case .guru:
            guard let action = body.action else { throw Problem("Say add, edit, or remove.") }
            guard let guru = body.guru, (1...100).contains(guru.trimmingCharacters(in: .whitespaces).count) else {
                throw Problem("Name the guru, in up to 100 characters.")
            }
            if let rename = body.rename, !(1...100).contains(rename.trimmingCharacters(in: .whitespaces).count) {
                throw Problem("A guru's name is 1 to 100 characters.")
            }
            if let playbook = body.playbook, playbook.count > tradingPlaybookMaxLength {
                throw Problem("A playbook is at most \(tradingPlaybookMaxLength) characters.")
            }
            if let minutes = body.repeatWindowMinutes, !(0...maximumRepeatWindowMinutes).contains(minutes) {
                throw Problem("The re-post window is 0 to \(maximumRepeatWindowMinutes) minutes.")
            }
            if let full = body.fullPositionUSD, !(1...32).contains(full.count) {
                throw Problem("The full position is a dollar amount.")
            }
            let edit = Guru(
                action: action, guru: guru.trimmingCharacters(in: .whitespaces),
                rename: body.rename?.trimmingCharacters(in: .whitespaces),
                channelID: try body.channelID.map { try discordID($0, field: "channel_id", empty: true) },
                authorID: try body.authorID.map { try discordID($0, field: "author_id", empty: true) },
                accountID: try body.accountID.map { try accountName($0, field: "account_id") },
                fullPositionUSD: body.fullPositionUSD, playbook: body.playbook,
                repeatWindowMinutes: body.repeatWindowMinutes)
            let changes =
                [
                    edit.rename, edit.channelID, edit.authorID, edit.accountID, edit.fullPositionUSD, edit.playbook,
                ].contains { $0 != nil } || edit.repeatWindowMinutes != nil
            switch action {
            case .remove where changes: throw Problem("Removing a guru takes only their name.")
            case .add where edit.rename != nil: throw Problem("A new guru is named once.")
            case .edit where !changes: throw Problem("Name at least one thing to change.")
            default: return .guru(edit)
            }
        case .alerts:
            var service: TradingAlertService?
            if let name = body.service {
                guard let known = TradingAlertService(rawValue: name) else {
                    throw Problem("Alerts go by telegram or discord.")
                }
                service = known
            }
            if let chat = body.chatID, chat.count > 64 { throw Problem("A chat ID is at most 64 characters.") }
            let edit = Alerts(
                enabled: body.enabled, service: service, chatID: body.chatID, token: try secret(body.token, field: "token"))
            guard edit.enabled != nil || edit.service != nil || edit.chatID != nil || edit.token != nil else {
                throw Problem("Name at least one thing to change.")
            }
            return .alerts(edit)
        case .importSetup:
            guard let text = body.text, (1...importMaximumCharacters).contains(text.count) else {
                throw Problem("The setup file is empty or larger than a setup file can be.")
            }
            return .importText(AgentSecret(text))
        }
    }

    private static func quoted(_ text: String) -> String { "“\(text.prefix(40))”" }

    private static func secret(_ value: String?, field: String) throws -> AgentSecret? {
        guard let value else { return nil }
        guard (1...4096).contains(value.count) else { throw Problem("The \(field) is empty or too long.") }
        return AgentSecret(value)
    }

    private static func accountName(_ value: String?, field: String) throws -> String {
        guard let value, value.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
            throw Problem("An account name (\(field)) is 1 to 64 letters, digits, “-” or “_”.")
        }
        return value
    }

    private static func discordID(_ value: String, field: String, empty: Bool) throws -> String {
        if empty && value.isEmpty { return value }
        guard (1...32).contains(value.count), value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw Problem("Discord IDs (\(field)) are digits only.")
        }
        return value
    }

    private static func discordIDs(_ values: [String], field: String, atLeastOne: Bool) throws -> [String] {
        guard values.count <= 50, !atLeastOne || !values.isEmpty else {
            throw Problem(atLeastOne ? "Give at least one channel ID." : "Give at most 50 author IDs.")
        }
        return try values.map { try discordID($0, field: field, empty: false) }
    }

    private struct Header: Decodable {
        let schemaVersion: Int?
        let requestID: String?
        let operation: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case requestID = "request_id"
            case operation
        }
    }

    private struct Body: Decodable {
        let channelIDs: [String]?
        let authorIDs: [String]?
        let token: String?
        let service: String?
        let model: String?
        let baseURL: String?
        let key: String?
        let action: Action?
        let accountID: String?
        let rename: String?
        let environment: String?
        let secret: String?
        let limits: [AgentLimitChange]?
        let recoveryPreference: String?
        let guru: String?
        let channelID: String?
        let authorID: String?
        let fullPositionUSD: String?
        let playbook: String?
        let repeatWindowMinutes: Int?
        let enabled: Bool?
        let chatID: String?
        let text: String?
        let start: Bool?

        enum CodingKeys: String, CodingKey {
            case channelIDs = "channel_ids"
            case authorIDs = "author_ids"
            case token
            case service
            case model
            case baseURL = "base_url"
            case key
            case action
            case accountID = "account_id"
            case rename
            case environment
            case secret
            case limits
            case recoveryPreference = "recovery_preference"
            case guru
            case channelID = "channel_id"
            case authorID = "author_id"
            case fullPositionUSD = "full_position_usd"
            case playbook
            case repeatWindowMinutes = "repeat_window_minutes"
            case enabled
            case chatID = "chat_id"
            case text
            case start
        }
    }
}

// Responses, encoded exactly as the contract's models read them.

/// Where a key stands: never its value.
public enum AgentKeyState: String, Encodable, Equatable, Sendable {
    case saved
    case missing
    /// Typed into the unsaved setup; the Keychain gets it when the setup is applied.
    case entered
    /// A model on the owner's own machine needs none.
    case notNeeded = "not_needed"
}

/// A connection's latest check, as its row in Connections reads.
public struct AgentSetupCheck: Encodable, Equatable, Sendable {
    public enum Connection: String, Encodable, Sendable {
        case discord
        case model
        case account
        case alerts
        case setup
    }

    public enum State: String, Encodable, Sendable {
        case passed
        case failed
        case notConfigured = "not_configured"
    }

    public var connection: Connection
    public var subject: String?
    public var state: State
    public var reason: String?
    /// What happened and what to do, set when the check failed.
    public var message: String?

    public init(connection: Connection, subject: String?, state: State, reason: String?, message: String?) {
        self.connection = connection
        self.subject = subject
        self.state = state
        self.reason = reason
        self.message = message
    }
}

public struct AgentSetupView: Encodable, Equatable, Sendable {
    public struct Discord: Encodable, Equatable, Sendable {
        public var channelIDs: [String]
        public var authorIDs: [String]
        public var token: AgentKeyState
        public var check: AgentSetupCheck?

        public init(channelIDs: [String], authorIDs: [String], token: AgentKeyState, check: AgentSetupCheck?) {
            self.channelIDs = channelIDs
            self.authorIDs = authorIDs
            self.token = token
            self.check = check
        }

        enum CodingKeys: String, CodingKey {
            case channelIDs = "channel_ids"
            case authorIDs = "author_ids"
            case token
            case check
        }
    }

    public struct Model: Encodable, Equatable, Sendable {
        public var service: String
        public var model: String
        public var baseURL: String?
        public var key: AgentKeyState
        public var check: AgentSetupCheck?

        public init(service: String, model: String, baseURL: String?, key: AgentKeyState, check: AgentSetupCheck?) {
            self.service = service
            self.model = model
            self.baseURL = baseURL
            self.key = key
            self.check = check
        }

        enum CodingKeys: String, CodingKey {
            case service
            case model
            case baseURL = "base_url"
            case key
            case check
        }
    }

    public struct Account: Encodable, Equatable, Sendable {
        public var accountID: String
        public var environment: TradingEnvironment
        public var keys: AgentKeyState
        public var limits: [AgentLimitChange]
        public var recoveryPreference: RecoveryPreference
        public var check: AgentSetupCheck?

        public init(
            accountID: String, environment: TradingEnvironment, keys: AgentKeyState, limits: [AgentLimitChange],
            recoveryPreference: RecoveryPreference, check: AgentSetupCheck?
        ) {
            self.accountID = accountID
            self.environment = environment
            self.keys = keys
            self.limits = limits
            self.recoveryPreference = recoveryPreference
            self.check = check
        }

        enum CodingKeys: String, CodingKey {
            case accountID = "account_id"
            case environment
            case keys
            case limits
            case recoveryPreference = "recovery_preference"
            case check
        }
    }

    public struct Guru: Encodable, Equatable, Sendable {
        /// The ID the guru's channel gives them (`GuruIdentity`); nil until they have a channel.
        public var guruID: String?
        public var name: String
        public var channelID: String?
        public var authorID: String?
        public var accountID: String?
        public var fullPositionUSD: String?
        public var repeatWindowMinutes: Int?
        public var playbookCharacters: Int

        public init(
            guruID: String?, name: String, channelID: String?, authorID: String?, accountID: String?,
            fullPositionUSD: String?, repeatWindowMinutes: Int?, playbookCharacters: Int
        ) {
            self.guruID = guruID
            self.name = name
            self.channelID = channelID
            self.authorID = authorID
            self.accountID = accountID
            self.fullPositionUSD = fullPositionUSD
            self.repeatWindowMinutes = repeatWindowMinutes
            self.playbookCharacters = playbookCharacters
        }

        enum CodingKeys: String, CodingKey {
            case guruID = "guru_id"
            case name
            case channelID = "channel_id"
            case authorID = "author_id"
            case accountID = "account_id"
            case fullPositionUSD = "full_position_usd"
            case repeatWindowMinutes = "repeat_window_minutes"
            case playbookCharacters = "playbook_characters"
        }
    }

    public struct Alerts: Encodable, Equatable, Sendable {
        public var enabled: Bool
        public var service: TradingAlertService
        public var chatID: String?
        public var token: AgentKeyState
        public var check: AgentSetupCheck?

        public init(
            enabled: Bool, service: TradingAlertService, chatID: String?, token: AgentKeyState, check: AgentSetupCheck?
        ) {
            self.enabled = enabled
            self.service = service
            self.chatID = chatID
            self.token = token
            self.check = check
        }

        enum CodingKeys: String, CodingKey {
            case enabled
            case service
            case chatID = "chat_id"
            case token
            case check
        }
    }

    public let type = "setup"
    public var saved: Bool
    public var unsavedChanges: Bool
    /// One of the five words, as its code: copying, sells_only, paused, stopped, not_started.
    public var copying: String
    public var discord: Discord
    public var model: Model
    public var accounts: [Account]
    public var gurus: [Guru]
    public var alerts: Alerts

    public init(
        saved: Bool, unsavedChanges: Bool, copying: String, discord: Discord, model: Model, accounts: [Account],
        gurus: [Guru], alerts: Alerts
    ) {
        self.saved = saved
        self.unsavedChanges = unsavedChanges
        self.copying = copying
        self.discord = discord
        self.model = model
        self.accounts = accounts
        self.gurus = gurus
        self.alerts = alerts
    }

    enum CodingKeys: String, CodingKey {
        case type
        case saved
        case unsavedChanges = "unsaved_changes"
        case copying
        case discord
        case model
        case accounts
        case gurus
        case alerts
    }
}

public struct AgentSetupImported: Encodable, Equatable, Sendable {
    public let type = "setup_imported"
    /// What the file filled and what the setup still needs, by name; never a value.
    public var filled: [String]
    public var missing: [String]
    public var setup: AgentSetupView

    public init(filled: [String], missing: [String], setup: AgentSetupView) {
        self.filled = filled
        self.missing = missing
        self.setup = setup
    }

    enum CodingKeys: String, CodingKey {
        case type
        case filled
        case missing
        case setup
    }
}

public struct AgentSetupApplied: Encodable, Equatable, Sendable {
    public enum Status: String, Encodable, Sendable {
        /// Checked, saved, and copying uses it.
        case applied
        /// Nothing to apply: copying already uses the saved setup.
        case unchanged
        /// A connection needs attention; nothing was saved.
        case failedChecks = "failed_checks"
        /// It did not take effect; the message says why.
        case failed
    }

    public let type = "setup_applied"
    public var status: Status
    public var message: String?
    public var checks: [AgentSetupCheck]

    public init(status: Status, message: String?, checks: [AgentSetupCheck] = []) {
        self.status = status
        self.message = message
        self.checks = checks
    }

    /// The code an approved apply reports to the engine; nil once it took effect.
    public var failureCode: String? {
        switch status {
        case .applied, .unchanged: nil
        case .failedChecks: "failed_checks"
        case .failed: "failed"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case status
        case message
        case checks
    }
}

public enum AgentSetupResult: Equatable, Sendable {
    case setup(AgentSetupView)
    case imported(AgentSetupImported)
    case applied(AgentSetupApplied)
}

/// Contract response lines for setup requests, which the app answers itself.
public enum AgentSetupResponse {
    public static func line(requestID: String, result: AgentSetupResult) -> String {
        switch result {
        case .setup(let view): encode(Envelope(requestID: requestID, ok: view))
        case .imported(let imported): encode(Envelope(requestID: requestID, ok: imported))
        case .applied(let applied): encode(Envelope(requestID: requestID, ok: applied))
        }
    }

    public static func errorLine(requestID: String, code: String, message: String) -> String {
        encode(Failure(requestID: requestID, error: .init(code: code, message: message)))
    }

    private static func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private struct Envelope<Result: Encodable>: Encodable {
        let schemaVersion = 1
        let requestID: String
        let ok: Result

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case requestID = "request_id"
            case ok
        }
    }

    private struct Failure: Encodable {
        struct Body: Encodable {
            let code: String
            let message: String
        }

        let schemaVersion = 1
        let requestID: String
        let error: Body

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case requestID = "request_id"
            case error
        }
    }
}

/// What applying the unsaved setup would do to live accounts, for the engine to decide whether
/// the owner must approve. Names only: the keys stay in the app.
public struct AgentSetupApplyFacts: Codable, Equatable, Sendable {
    public var madeLive: [String]
    public var newLiveKeys: [String]
    public var changedLive: [String]
    public var startsLive: [String]

    public init(madeLive: [String] = [], newLiveKeys: [String] = [], changedLive: [String] = [], startsLive: [String] = []) {
        self.madeLive = madeLive
        self.newLiveKeys = newLiveKeys
        self.changedLive = changedLive
        self.startsLive = startsLive
    }

    public var touchesLive: Bool {
        !(madeLive.isEmpty && newLiveKeys.isEmpty && changedLive.isEmpty && startsLive.isEmpty)
    }

    enum CodingKeys: String, CodingKey {
        case madeLive = "made_live"
        case newLiveKeys = "new_live_keys"
        case changedLive = "changed_live"
        case startsLive = "starts_live"
    }
}

/// The setup request the app asks the engine about: its operation and, for an apply, its facts.
public struct AgentSetupAuthorizationRequest: Encodable, Equatable, Sendable {
    public let operation: AgentSetupOperation
    public let requestID: String
    public let apply: AgentSetupApplyFacts?
    /// The app could not read the line: the engine records who sent it, and refuses it.
    public let invalid: Bool

    public init(
        operation: AgentSetupOperation, requestID: String, apply: AgentSetupApplyFacts?, invalid: Bool = false
    ) {
        self.operation = operation
        self.requestID = requestID
        self.apply = apply
        self.invalid = invalid
    }

    enum CodingKeys: String, CodingKey {
        case operation
        case requestID = "request_id"
        case apply
        case invalid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation, forKey: .operation)
        try container.encode(requestID, forKey: .requestID)
        try container.encodeIfPresent(apply, forKey: .apply)
        if invalid { try container.encode(true, forKey: .invalid) }
    }
}

/// The engine's word on a setup request: run it now, or answer with this contract line (a
/// refusal, or a proposal the owner approves in the app).
public enum AgentSetupAuthorization: Equatable, Sendable {
    case allowed
    case answered(line: String)
}
