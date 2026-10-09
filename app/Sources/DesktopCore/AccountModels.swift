import Foundation

public enum AccountControlAction: String, Codable, Sendable {
    case pause
    case resume
    case setRecovery = "set_recovery"
}

public enum RecoveryPreference: String, Codable, CaseIterable, Sendable {
    case manual
    case automatic
}

public struct AccountControlCommand: Codable, Equatable, Sendable {
    public let commandID: String
    public let accountID: String
    public let action: AccountControlAction
    public let recoveryPreference: RecoveryPreference?

    public init(
        commandID: String, accountID: String, action: AccountControlAction,
        recoveryPreference: RecoveryPreference? = nil
    ) {
        self.commandID = commandID
        self.accountID = accountID
        self.action = action
        self.recoveryPreference = recoveryPreference
    }

    enum CodingKeys: String, CodingKey {
        case commandID = "command_id"
        case accountID = "account_id"
        case action
        case recoveryPreference = "recovery_preference"
    }
}

public struct AccountControlResult: Codable, Equatable, Sendable {
    public let command: AccountControlCommand
    public let appliedAt: String
    public let entryPermission: String
    public let recoveryPreference: RecoveryPreference

    enum CodingKeys: String, CodingKey {
        case command
        case appliedAt = "applied_at"
        case entryPermission = "entry_permission"
        case recoveryPreference = "recovery_preference"
    }
}

public struct OwnershipResolutionRequest: Codable, Equatable, Sendable {
    public let resolutionID: String
    public let incidentID: String
    public let accountID: String
    public let symbol: String
    public let actor: String
    public let reason: String
    public let brokerQty: String
    public let externalQty: String
    public let lotRemaining: [String: String]

    public init(
        resolutionID: String, incidentID: String, accountID: String,
        symbol: String, actor: String, reason: String, brokerQty: String,
        externalQty: String, lotRemaining: [String: String]
    ) {
        self.resolutionID = resolutionID
        self.incidentID = incidentID
        self.accountID = accountID
        self.symbol = symbol
        self.actor = actor
        self.reason = reason
        self.brokerQty = brokerQty
        self.externalQty = externalQty
        self.lotRemaining = lotRemaining
    }

    enum CodingKeys: String, CodingKey {
        case resolutionID = "resolution_id"
        case incidentID = "incident_id"
        case accountID = "account_id"
        case symbol, actor, reason
        case brokerQty = "broker_qty"
        case externalQty = "external_qty"
        case lotRemaining = "lot_remaining"
    }
}

public struct OwnershipResolution: Codable, Equatable, Sendable {
    public let request: OwnershipResolutionRequest
    public let checkedAt: String
    public let lotReductions: [String: String]
    public let allocationRevision: Int

    enum CodingKeys: String, CodingKey {
        case request
        case checkedAt = "checked_at"
        case lotReductions = "lot_reductions"
        case allocationRevision = "allocation_revision"
    }
}

public struct AccountPositionView: Codable, Equatable, Identifiable, Sendable {
    public let symbol: String
    public let ownedQty: String
    public let externalQty: String
    public let brokerQty: String?
    /// What CopyTrading bought, oldest first, each with the post that bought it.
    public let lots: [AccountLotView]
    /// The broker's valuation of the whole position; nil when the broker was not read.
    public let avgEntryPrice: String?
    public let currentPrice: String?
    public let marketValue: String?
    public let unrealizedPL: String?
    /// The gain or loss as a fraction of cost: 0.04 is 4%.
    public let unrealizedPLPercent: String?
    public var id: String { symbol }

    enum CodingKeys: String, CodingKey {
        case symbol
        case ownedQty = "owned_qty"
        case externalQty = "external_qty"
        case brokerQty = "broker_qty"
        case lots
        case avgEntryPrice = "avg_entry_price"
        case currentPrice = "current_price"
        case marketValue = "market_value"
        case unrealizedPL = "unrealized_pl"
        case unrealizedPLPercent = "unrealized_plpc"
    }
}

/// One block of shares CopyTrading bought for an account, and the post that bought it. The source
/// fields are missing only when the buy that opened the lot is no longer on record.
public struct AccountLotView: Codable, Equatable, Identifiable, Sendable {
    public let lotID: String
    public let sourceID: String?
    public let guruID: String?
    public let postedAt: String?
    public let excerpt: String?
    public let boughtAt: String?
    public let originalQty: String
    public let remainingQty: String
    public let averagePrice: String
    /// The lot's remaining shares at the broker's current price, against what they cost.
    public let unrealizedPL: String?
    public var id: String { lotID }

    enum CodingKeys: String, CodingKey {
        case lotID = "lot_id"
        case sourceID = "source_id"
        case guruID = "guru_id"
        case postedAt = "posted_at"
        case excerpt
        case boughtAt = "bought_at"
        case originalQty = "original_qty"
        case remainingQty = "remaining_qty"
        case averagePrice = "average_price"
        case unrealizedPL = "unrealized_pl"
    }
}

public struct OwnershipIncidentView: Codable, Equatable, Identifiable, Sendable {
    public let incidentID: String
    public let symbol: String
    public let expectedQty: String
    public let actualQty: String
    public let observedAt: String
    public let cause: String
    public var id: String { incidentID }

    enum CodingKeys: String, CodingKey {
        case incidentID = "incident_id"
        case symbol
        case expectedQty = "expected_qty"
        case actualQty = "actual_qty"
        case observedAt = "observed_at"
        case cause
    }
}

/// The broker's own valuation of an account at `observedAt`.
public struct AccountBalance: Codable, Equatable, Sendable {
    public let equity: String
    public let previousCloseEquity: String
    public let dayChangeUSD: String
    public let cash: String
    public let buyingPower: String
    public let observedAt: String

    enum CodingKeys: String, CodingKey {
        case equity
        case previousCloseEquity = "previous_close_equity"
        case dayChangeUSD = "day_change_usd"
        case cash
        case buyingPower = "buying_power"
        case observedAt = "observed_at"
    }
}

public struct AccountOverview: Codable, Equatable, Identifiable, Sendable {
    public let accountID: String
    public let environment: TradingEnvironment
    public let activeConfiguration: Bool
    public let brokerIdentity: String
    public let entryPermission: String
    public let recoveryPreference: RecoveryPreference
    public let readiness: String
    public let accountRiskStatus: String
    public let accountRiskReason: String?
    public let accountActivityStatus: String
    public let accountActivityReason: String?
    public let totalExposureUSD: String?
    public let appCostBasisUSD: String?
    public let positions: [AccountPositionView]
    public let unresolvedIncidents: [String]
    public let ownershipIncidents: [OwnershipIncidentView]
    public let pendingOrders: Int?
    public let balance: AccountBalance?

    public var id: String { accountID }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case environment
        case activeConfiguration = "active_configuration"
        case brokerIdentity = "broker_identity"
        case entryPermission = "entry_permission"
        case recoveryPreference = "recovery_preference"
        case readiness
        case accountRiskStatus = "account_risk_status"
        case accountRiskReason = "account_risk_reason"
        case accountActivityStatus = "account_activity_status"
        case accountActivityReason = "account_activity_reason"
        case totalExposureUSD = "total_exposure_usd"
        case appCostBasisUSD = "app_cost_basis_usd"
        case positions
        case unresolvedIncidents = "unresolved_incidents"
        case ownershipIncidents = "ownership_incidents"
        case pendingOrders = "pending_orders"
        case balance
    }
}

/// An account whose evidence the engine could not read for a page; it is never shown as empty.
public struct AccountUnavailable: Codable, Equatable, Identifiable, Sendable {
    public let accountID: String
    public let reason: String

    public var id: String { accountID }

    public var explanation: String {
        reason == "timeout" ? "did not answer in time" : "could not be read"
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case reason
    }
}

public struct AccountOverviewPage: Codable, Equatable, Sendable {
    public let items: [AccountOverview]
    public let nextBeforeAccountID: String?
    public let unavailableAccounts: [AccountUnavailable]

    enum CodingKeys: String, CodingKey {
        case items
        case nextBeforeAccountID = "next_before_account_id"
        case unavailableAccounts = "unavailable_accounts"
    }
}

public struct OrderActivity: Codable, Equatable, Identifiable, Sendable {
    public let clientID: String
    public let symbol: String
    public let side: String
    public let status: String
    public let quantity: String
    public let filledQuantity: String
    public let limitPrice: String?
    public let averageFillPrice: String?
    public let brokerID: String?
    public let createdAt: String
    /// Which of the post's calls this order places.
    public let instructionIndex: Int
    /// For a buy: what the call asked for, and what the maximum per order allowed of it.
    public let requestedUSD: String?
    public let budgetUSD: String?
    /// How it went out: "limit" or "market", in which session, from which guru price, and how far
    /// above it a buy could pay.
    public let orderType: String?
    public let session: String?
    public let sourcePrice: String?
    public let entryTolerancePct: String?
    public let submittedAt: String?
    /// The market when it went out.
    public let quoteBid: String?
    public let quoteAsk: String?
    /// Why it ended unfilled: timeout, replaced_by_sell, copying_stopped, cancelled_at_broker,
    /// expired, or rejected.
    public let cancelReason: String?
    public let endedAt: String?
    public var id: String { clientID }

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case symbol, side, status, quantity
        case filledQuantity = "filled_quantity"
        case limitPrice = "limit_price"
        case averageFillPrice = "average_fill_price"
        case brokerID = "broker_id"
        case createdAt = "created_at"
        case instructionIndex = "instruction_index"
        case requestedUSD = "requested_usd"
        case budgetUSD = "budget_usd"
        case orderType = "order_type"
        case session
        case sourcePrice = "source_price"
        case entryTolerancePct = "entry_tolerance_pct"
        case submittedAt = "submitted_at"
        case quoteBid = "quote_bid"
        case quoteAsk = "quote_ask"
        case cancelReason = "cancel_reason"
        case endedAt = "ended_at"
    }
}

/// One moment of a post's trip through an account: received, held, sized, sent, accepted,
/// filled, cancelled… with its time.
public struct TimelineStep: Codable, Equatable, Sendable {
    public let step: String
    public let at: String
    public let clientID: String?
    public let reason: String?
    public let quantity: String?
    public let price: String?

    enum CodingKeys: String, CodingKey {
        case step, at, reason, quantity, price
        case clientID = "client_id"
    }
}

/// The limit a skipped call would have passed, with its numbers.
public struct LimitHit: Codable, Equatable, Sendable {
    /// The call it skipped.
    public let part: Int
    /// "symbol" (the maximum per stock) or "total".
    public let scope: String
    public let current: String
    public let proposed: String
    public let limit: String
}

public struct DestinationActivity: Codable, Equatable, Identifiable, Sendable {
    public let accountID: String
    public let environment: String
    public let status: String
    public let instructionOutcomes: [String]
    public let limitsHit: [LimitHit]
    public let orders: [OrderActivity]
    /// Every step the post took in this account, in order.
    public let timeline: [TimelineStep]
    public var id: String { accountID }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case environment, status
        case instructionOutcomes = "instruction_outcomes"
        case limitsHit = "limits_hit"
        case orders, timeline
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try values.decode(String.self, forKey: .accountID)
        environment = try values.decode(String.self, forKey: .environment)
        status = try values.decode(String.self, forKey: .status)
        instructionOutcomes = try values.decode([String].self, forKey: .instructionOutcomes)
        limitsHit = try values.decode([LimitHit].self, forKey: .limitsHit)
        orders = try values.decode([OrderActivity].self, forKey: .orders)
        timeline = try values.decodeIfPresent([TimelineStep].self, forKey: .timeline) ?? []
    }
}

public struct SourceAttachmentEvidence: Codable, Equatable, Identifiable, Sendable {
    public let evidenceID: String
    public let attachmentID: String
    public let filename: String
    public let contentType: String?
    public let declaredSize: Int
    public let status: String
    public let byteSize: Int?
    public let sha256: String?
    public let omittedCount: Int

    public var id: String { evidenceID }

    enum CodingKeys: String, CodingKey {
        case evidenceID = "evidence_id"
        case attachmentID = "attachment_id"
        case filename
        case contentType = "content_type"
        case declaredSize = "declared_size"
        case status
        case byteSize = "byte_size"
        case sha256
        case omittedCount = "omitted_count"
    }
}

public struct SourceEmbedFieldEvidence: Codable, Equatable, Sendable {
    public let name: String
    public let value: String
    public let inline: Bool
}

public struct SourceEmbedEvidence: Codable, Equatable, Sendable {
    public let title: String?
    public let description: String?
    public let fields: [SourceEmbedFieldEvidence]
}

public struct SourceEventEvidence: Codable, Equatable, Sendable {
    public let eventType: String
    public let messageID: String?
    public let channelID: String?
    public let authorID: String?
    public let timestamp: String?
    public let content: String
    public let embeds: [SourceEmbedEvidence]
    public let attachments: [SourceAttachmentEvidence]
    public let attachmentsOmitted: Int
    public let captureStatus: String
    public let payloadBytes: Int

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case messageID = "message_id"
        case channelID = "channel_id"
        case authorID = "author_id"
        case timestamp
        case content, embeds, attachments
        case attachmentsOmitted = "attachments_omitted"
        case captureStatus = "capture_status"
        case payloadBytes = "payload_bytes"
    }
}

public struct RejectedSourceActivity: Codable, Equatable, Identifiable, Sendable {
    public let sourceID: String
    public let rejectedAt: String
    public let reason: String
    public let sourceEvent: SourceEventEvidence
    public var id: String { sourceID }

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case rejectedAt = "rejected_at"
        case reason
        case sourceEvent = "source_event"
    }
}

/// One call as the engine places it, before any account sizing. A sell with no entry price sells
/// from every buy of the stock (ADR-0010).
public struct SourceInstruction: Codable, Equatable, Sendable {
    public let action: String
    public let symbol: String
    /// The guru's price; nil for a sell at the market, priced from the live bid (ADR-0007).
    public let price: String?
    public let entryPrice: String?
    public let fraction: String?
    public let exitBasis: String?

    enum CodingKeys: String, CodingKey {
        case action, symbol, price, fraction
        case entryPrice = "entry_price"
        case exitBasis = "exit_basis"
    }
}

public struct SourceActivity: Codable, Equatable, Identifiable, Sendable {
    public let sequence: Int
    public let sourceID: String
    public let sourceRevision: Int
    public let authorID: String?
    public let guruID: String?
    public let profileRevision: String?
    public let sourceAt: String
    public let capturedAt: String
    public let text: String
    public let captureStatus: String
    public let parseStatus: String
    public let deliveryStatus: String
    public let decision: String?
    public let parserReason: String?
    public let parserProfile: String?
    public let interpretedBy: String?
    public let instructions: [SourceInstruction]
    /// For a post that waits for the owner: what Copy places (ADR-0007).
    public let suggested: [SourceInstruction]
    /// How the reader read the post; nil for a post never read.
    public let reading: PostReading?
    public let sourceEvent: SourceEventEvidence
    public let destinations: [DestinationActivity]
    /// When the reader took the post, when it finished, and when the reading reached the accounts.
    public let readStartedAt: String?
    public let readAt: String?
    public let deliveredAt: String?
    public var id: Int { sequence }

    enum CodingKeys: String, CodingKey {
        case sequence
        case sourceID = "source_id"
        case sourceRevision = "source_revision"
        case authorID = "author_id"
        case guruID = "guru_id"
        case profileRevision = "profile_revision"
        case sourceAt = "source_at"
        case capturedAt = "captured_at"
        case text
        case captureStatus = "capture_status"
        case parseStatus = "parse_status"
        case deliveryStatus = "delivery_status"
        case decision
        case parserReason = "parser_reason"
        case parserProfile = "parser_profile"
        case interpretedBy = "interpreted_by"
        case instructions
        case suggested
        case reading
        case sourceEvent = "source_event"
        case destinations
        case readStartedAt = "read_started_at"
        case readAt = "read_at"
        case deliveredAt = "delivered_at"
    }
}

public struct SourceActivityPage: Codable, Equatable, Sendable {
    public let items: [SourceActivity]
    public let rejectedItems: [RejectedSourceActivity]
    public let nextBeforeSeq: Int?
    public let unavailableAccounts: [AccountUnavailable]
    enum CodingKeys: String, CodingKey {
        case items
        case rejectedItems = "rejected_items"
        case nextBeforeSeq = "next_before_seq"
        case unavailableAccounts = "unavailable_accounts"
    }
}

/// One row of an account's feed: an order that filled or ended, a sale the owner made, or a
/// change the owner made to the account. Amounts are engine decimals.
public struct AccountFeedItem: Codable, Equatable, Identifiable, Sendable {
    public let sequence: Int
    public let at: String
    /// bought, sold, cancelled, expired, rejected, paused, resumed, settled, or limits_changed.
    public let kind: String
    /// guru (a post was copied) or you (the owner did it).
    public let source: String
    public let side: String?
    public let symbol: String?
    public let shares: String?
    public let price: String?
    public let amount: String?
    public let guruID: String?
    public let messageID: String?
    public let orderID: String?
    /// The limits the owner changed, for a `limits_changed` row.
    public let changes: [AccountLimitChange]
    /// Why a `settled` row's holdings count was settled: the owner answered, or the broker's
    /// filled count showed shares bought or sold outside CopyTrading.
    public let reason: String?
    public var id: Int { sequence }

    enum CodingKeys: String, CodingKey {
        case sequence, at, kind, source, side, symbol, shares, price, amount, changes, reason
        case guruID = "guru_id"
        case messageID = "message_id"
        case orderID = "order_id"
    }
}

/// One limit the owner changed: its engine policy name, and its value before and after as text.
public struct AccountLimitChange: Codable, Equatable, Sendable {
    public let setting: String
    public let before: String
    public let after: String

    public init(setting: String, before: String, after: String) {
        self.setting = setting
        self.before = before
        self.after = after
    }
}

public struct AccountFeedPage: Codable, Equatable, Sendable {
    public let accountID: String
    public let items: [AccountFeedItem]
    public let nextBeforeSeq: Int?
    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case items
        case nextBeforeSeq = "next_before_seq"
    }
}

public enum EquityHistoryRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case threeMonths = "three_months"
    case year

    public var id: String { rawValue }
}

/// A stretch of the broker's equity curve: a range ending now, or one chosen trading day.
public struct EquityHistoryWindow: Codable, Hashable, Sendable {
    public let range: EquityHistoryRange
    /// The chosen trading day as `yyyy-MM-dd`, only for the day range; nil means the latest.
    public let day: String?

    public init(range: EquityHistoryRange, day: String? = nil) {
        self.range = range
        self.day = range == .day ? day : nil
    }

    public static let today = EquityHistoryWindow(range: .day)
}

public struct EquityPoint: Codable, Equatable, Sendable {
    public let at: String
    public let equity: String
}

/// The broker's equity curve for one account and window, oldest point first.
public struct EquityHistory: Codable, Equatable, Sendable {
    public let window: EquityHistoryWindow
    public let baseValue: String?
    public let points: [EquityPoint]

    enum CodingKeys: String, CodingKey {
        case window
        case baseValue = "base_value"
        case points
    }
}
