import Foundation

public enum ManualInstructionAction: String, Codable, CaseIterable, Sendable {
    case buy
    case reduce
    case close
}

public struct ManualInstruction: Codable, Equatable, Sendable {
    public let action: ManualInstructionAction
    public let symbol: String
    /// The guru's price; nil for a sell at the market, priced from the live bid (ADR-0007).
    public let price: String?
    public let entryPrice: String?
    public let fraction: String?
    public let exitBasis: String?

    public init(
        action: ManualInstructionAction,
        symbol: String,
        price: String?,
        entryPrice: String? = nil,
        fraction: String? = nil,
        exitBasis: String? = nil
    ) {
        self.action = action
        self.symbol = symbol
        self.price = price
        self.entryPrice = entryPrice
        self.fraction = fraction
        self.exitBasis = exitBasis
    }

    enum CodingKeys: String, CodingKey {
        case action, symbol, price, fraction
        case entryPrice = "entry_price"
        case exitBasis = "exit_basis"
    }

    /// The engine requires `price` on every instruction, as null for a sell at the market.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(price, forKey: .price)
        try container.encodeIfPresent(entryPrice, forKey: .entryPrice)
        try container.encodeIfPresent(fraction, forKey: .fraction)
        try container.encodeIfPresent(exitBasis, forKey: .exitBasis)
    }
}

public struct ManualEvidence: Codable, Equatable, Sendable {
    public let action: ManualInstructionAction
    public let symbol: String
    public let price: String
    public let entryPrice: String?
    public let fraction: String?
    public let actionEvidence: String
    public let symbolEvidence: String
    public let priceEvidence: String
    public let entryEvidence: String?
    public let fractionEvidence: String?

    enum CodingKeys: String, CodingKey {
        case action, symbol, price, fraction
        case entryPrice = "entry_price"
        case actionEvidence = "action_evidence"
        case symbolEvidence = "symbol_evidence"
        case priceEvidence = "price_evidence"
        case entryEvidence = "entry_evidence"
        case fractionEvidence = "fraction_evidence"
    }
}

public struct ManualAcceptedInterpretation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let eventType: String
    public let source: String
    public let channelID: String
    public let id: String
    public let timestamp: String
    public let text: String
    public let parserProfile: String
    public let model: String
    public let decision: String
    public let reason: String
    public let evidence: [ManualEvidence]
    public let instructions: [ManualInstruction]

    enum CodingKeys: String, CodingKey {
        case source, id, timestamp, text, model, decision, reason, evidence, instructions
        case schemaVersion = "schema_version"
        case eventType = "event_type"
        case channelID = "channel_id"
        case parserProfile = "parser_profile"
    }
}

public struct ManualCorrectionRequest: Codable, Equatable, Sendable {
    public let correctionID: String
    public let sourceID: String
    public let selectedAccountIDs: [String]
    public let actor: String
    public let reason: String
    public let instructions: [ManualInstruction]

    public init(
        correctionID: String,
        sourceID: String,
        selectedAccountIDs: [String],
        actor: String,
        reason: String,
        instructions: [ManualInstruction]
    ) {
        self.correctionID = correctionID
        self.sourceID = sourceID
        self.selectedAccountIDs = Array(Set(selectedAccountIDs)).sorted()
        self.actor = actor
        self.reason = reason
        self.instructions = instructions
    }

    enum CodingKeys: String, CodingKey {
        case correctionID = "correction_id"
        case sourceID = "source_id"
        case selectedAccountIDs = "selected_account_ids"
        case actor, reason, instructions
    }
}

public struct ManualCorrectionRecord: Codable, Equatable, Identifiable, Sendable {
    public let correctionID: String
    public let sourceID: String
    public let selectedAccountIDs: [String]
    public let revision: Int
    public let actor: String
    public let reason: String
    public let instructions: [ManualInstruction]
    public let sourceRevision: Int
    public let sourceAt: String
    public let sourceText: String
    public let acceptedInterpretation: ManualAcceptedInterpretation
    public let recordedAt: String
    public var id: String { correctionID }

    enum CodingKeys: String, CodingKey {
        case correctionID = "correction_id"
        case sourceID = "source_id"
        case selectedAccountIDs = "selected_account_ids"
        case revision, actor, reason, instructions
        case sourceRevision = "source_revision"
        case sourceAt = "source_at"
        case sourceText = "source_text"
        case acceptedInterpretation = "accepted_interpretation"
        case recordedAt = "recorded_at"
    }
}

public struct ManualCorrectionAccountResult: Codable, Equatable, Identifiable, Sendable {
    public let accountID: String
    public let status: String
    public let reason: String?
    public var id: String { accountID }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case status, reason
    }
}

public struct ManualCorrectionOutcome: Codable, Equatable, Sendable {
    public let correction: ManualCorrectionRecord
    public let accounts: [ManualCorrectionAccountResult]
}

public struct ManualPreviewRequest: Codable, Equatable, Sendable {
    public let previewID: String
    public let accountID: String
    public let correctionID: String
    public let instructionIndex: Int

    public init(
        previewID: String, accountID: String, correctionID: String, instructionIndex: Int
    ) {
        self.previewID = previewID
        self.accountID = accountID
        self.correctionID = correctionID
        self.instructionIndex = instructionIndex
    }

    enum CodingKeys: String, CodingKey {
        case previewID = "preview_id"
        case accountID = "account_id"
        case correctionID = "correction_id"
        case instructionIndex = "instruction_index"
    }
}

public struct ManualQuote: Codable, Equatable, Sendable {
    public let feed: String
    public let bid: String?
    public let ask: String?
    public let timestamp: String?
}

public struct ManualOrderPlan: Codable, Equatable, Sendable {
    public let side: String
    public let positionIntent: String
    public let type: String
    public let limitPrice: String?
    public let symbol: String
    public let quantity: String
    public let sourcePrice: String
    public let entryTolerancePct: String
    public let lotID: String?
    public let entryPrice: String
    public let session: String

    enum CodingKeys: String, CodingKey {
        case side, type, symbol, session
        case positionIntent = "position_intent"
        case limitPrice = "limit_price"
        case quantity = "qty"
        case sourcePrice = "source_price"
        case entryTolerancePct = "entry_tolerance_pct"
        case lotID = "lot_id"
        case entryPrice = "entry_price"
    }
}

public struct ManualCheck: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let status: String
    public let reason: String?
    public var id: String { name }
}

public struct ManualOrderPreview: Codable, Equatable, Identifiable, Sendable {
    public let request: ManualPreviewRequest
    public let brokerAccountID: String
    public let environment: TradingEnvironment
    public let correctionRevision: Int
    public let sourceAt: String
    public let sourceAgeSeconds: Int
    public let instruction: ManualInstruction
    public let createdAt: String
    public let expiresAt: String
    public let session: String?
    public let quote: ManualQuote?
    public let freshPrice: String?
    public let plan: ManualOrderPlan?
    public let checks: [ManualCheck]
    public let reasons: [String]
    public let factsSHA256: String
    public let configurationSHA256: String
    public var id: String { request.previewID }

    enum CodingKeys: String, CodingKey {
        case request, environment, session, quote, plan, checks, reasons
        case brokerAccountID = "broker_account_id"
        case correctionRevision = "correction_revision"
        case sourceAt = "source_at"
        case sourceAgeSeconds = "source_age_seconds"
        case instruction
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case freshPrice = "fresh_price"
        case factsSHA256 = "facts_sha256"
        case configurationSHA256 = "configuration_sha256"
    }
}

public struct ManualConfirmationRequest: Codable, Equatable, Identifiable, Sendable {
    public let commandID: String
    public let previewID: String
    public let accountID: String
    public let actor: String
    public var id: String { commandID }

    public init(commandID: String, previewID: String, accountID: String, actor: String) {
        self.commandID = commandID
        self.previewID = previewID
        self.accountID = accountID
        self.actor = actor
    }

    enum CodingKeys: String, CodingKey {
        case commandID = "command_id"
        case previewID = "preview_id"
        case accountID = "account_id"
        case actor
    }
}

public struct ManualCommandRecord: Codable, Equatable, Sendable {
    public let request: ManualConfirmationRequest
    public let correctionID: String
    public let sourceID: String
    public let instructionIndex: Int
    public let confirmedAt: String
    public let state: String
    public let reason: String?
    public let clientID: String?

    enum CodingKeys: String, CodingKey {
        case request, state, reason
        case correctionID = "correction_id"
        case sourceID = "source_id"
        case instructionIndex = "instruction_index"
        case confirmedAt = "confirmed_at"
        case clientID = "client_id"
    }
}

public struct ManualCommandResult: Codable, Equatable, Sendable {
    public let command: ManualCommandRecord
    public let status: String
    public let reason: String?
    public let clientID: String?
    public let brokerOrderID: String?
    public let orderStatus: String?
    public let filledQuantity: String

    enum CodingKeys: String, CodingKey {
        case command, status, reason
        case clientID = "client_id"
        case brokerOrderID = "broker_order_id"
        case orderStatus = "order_status"
        case filledQuantity = "filled_qty"
    }
}

public struct ManualCommandPage: Codable, Equatable, Sendable {
    public let accountID: String
    public let sourceID: String
    public let items: [ManualCommandResult]
    public let nextBeforeCommandID: String?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case sourceID = "source_id"
        case items
        case nextBeforeCommandID = "next_before_command_id"
    }
}

public struct ManualAccountCommandResult: Codable, Equatable, Identifiable, Sendable {
    public let accountID: String
    public let commandID: String
    public let result: ManualCommandResult?
    public let error: String?
    public var id: String { accountID }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case commandID = "command_id"
        case result, error
    }
}

public struct ManualCommandsOutcome: Codable, Equatable, Sendable {
    public let outcomes: [ManualAccountCommandResult]
}
