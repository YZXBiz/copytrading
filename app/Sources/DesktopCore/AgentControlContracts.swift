import Foundation

/// How much the owner lets agents do through the `copytrading` CLI and MCP server.
public enum AgentAccessLevel: String, Codable, Equatable, Sendable {
    /// Read state and pause; proposals are refused.
    case readAndPause = "read_pause"
    /// Also create proposals that the owner approves in the app.
    case propose
}

/// What only the app knows about one agent request; the engine decides with it.
public struct AgentRequestContext: Encodable, Equatable, Sendable {
    public let accessLevel: AgentAccessLevel
    public let unlocked: Bool
    public let callerPID: Int32?
    public let callerPath: String?

    public init(accessLevel: AgentAccessLevel, unlocked: Bool, callerPID: Int32?, callerPath: String?) {
        self.accessLevel = accessLevel
        self.unlocked = unlocked
        self.callerPID = callerPID
        self.callerPath = callerPath
    }

    enum CodingKeys: String, CodingKey {
        case accessLevel = "access_level"
        case unlocked
        case callerPID = "caller_pid"
        case callerPath = "caller_path"
    }
}

/// The owner's stored choice; `off` means the app does not listen for agents at all.
public enum AgentAccessSetting: String, Codable, CaseIterable, Equatable, Sendable {
    case off
    case readAndPause = "read_pause"
    case propose

    public var accessLevel: AgentAccessLevel? {
        switch self {
        case .off: nil
        case .readAndPause: .readAndPause
        case .propose: .propose
        }
    }
}

/// A previewed manual order an agent asked the owner to place.
public struct AgentManualOrder: Decodable, Equatable, Sendable {
    public let accountID: String
    public let previewID: String
    public let environment: TradingEnvironment
    public let symbol: String
    public let side: String
    public let orderType: String
    public let quantity: String
    public let limitPrice: String?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case previewID = "preview_id"
        case environment
        case symbol
        case side
        case orderType = "order_type"
        case quantity
        case limitPrice = "limit_price"
    }
}

/// What an agent asked for; the engine performs it only after the owner approves this digest.
public struct AgentProposal: Decodable, Equatable, Identifiable, Sendable {
    public enum State: String, Decodable, Equatable, Sendable {
        case pending
        case running
        case succeeded
        case failed
        case outcomeUnknown = "outcome_unknown"
        case rejected
        case expired
        case discarded
    }

    public enum Subject: Equatable, Sendable {
        case resumeAccount(accountID: String)
        case setRecovery(accountID: String, preference: String)
        case manualOrder(AgentManualOrder)
    }

    public struct Caller: Decodable, Equatable, Sendable {
        public let pid: Int32?
        public let path: String?
    }

    public struct Outcome: Decodable, Equatable, Sendable {
        public let status: String
        public let code: String?
    }

    public let id: String
    public let state: State
    public let subject: Subject
    public let digest: String
    public let createdAt: String
    public let expiresAt: String
    public let requestedBy: Caller
    public let outcome: Outcome?

    enum CodingKeys: String, CodingKey {
        case id = "proposal_id"
        case state
        case subject
        case digest
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case requestedBy = "requested_by"
        case outcome
    }

    private enum SubjectKeys: String, CodingKey {
        case kind
        case accountID = "account_id"
        case preference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = try container.decode(State.self, forKey: .state)
        digest = try container.decode(String.self, forKey: .digest)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        expiresAt = try container.decode(String.self, forKey: .expiresAt)
        requestedBy = try container.decode(Caller.self, forKey: .requestedBy)
        outcome = try container.decodeIfPresent(Outcome.self, forKey: .outcome)
        let subject = try container.nestedContainer(keyedBy: SubjectKeys.self, forKey: .subject)
        switch try subject.decode(String.self, forKey: .kind) {
        case "resume_account":
            self.subject = .resumeAccount(accountID: try subject.decode(String.self, forKey: .accountID))
        case "set_recovery":
            self.subject = .setRecovery(
                accountID: try subject.decode(String.self, forKey: .accountID),
                preference: try subject.decode(String.self, forKey: .preference)
            )
        case "confirm_manual_order":
            self.subject = .manualOrder(try container.decode(AgentManualOrder.self, forKey: .subject))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: subject, debugDescription: "Unknown agent proposal kind."
            )
        }
    }
}

/// One agent-control decision from the engine's audit trail; identifiers only.
public struct AgentAuditEntry: Decodable, Equatable, Identifiable, Sendable {
    public let at: String
    public let actor: String
    public let callerPID: Int32?
    public let callerPath: String?
    public let operation: String
    public let tier: String?
    public let outcome: String
    public let proposalID: String?

    public var id: String { "\(at)|\(actor)|\(operation)|\(outcome)|\(proposalID ?? "")" }

    enum CodingKeys: String, CodingKey {
        case at
        case actor
        case callerPID = "caller_pid"
        case callerPath = "caller_path"
        case operation
        case tier
        case outcome
        case proposalID = "proposal_id"
    }
}
