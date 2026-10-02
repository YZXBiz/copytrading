import Foundation

/// Sell up to `quantity` shares of one lot CopyTrading bought for an account.
public struct LotSalePreviewRequest: Codable, Equatable, Sendable {
    public let previewID: String
    public let accountID: String
    public let lotID: String
    public let quantity: String

    public init(previewID: String, accountID: String, lotID: String, quantity: String) {
        self.previewID = previewID
        self.accountID = accountID
        self.lotID = lotID
        self.quantity = quantity
    }

    enum CodingKeys: String, CodingKey {
        case previewID = "preview_id"
        case accountID = "account_id"
        case lotID = "lot_id"
        case quantity = "qty"
    }
}

/// What a lot sale would do right now, checked against fresh broker facts. A plan is present only
/// when nothing blocks the sale; a preview expires about thirty seconds after it is made.
public struct LotSalePreview: Codable, Equatable, Identifiable, Sendable {
    public let request: LotSalePreviewRequest
    public let brokerAccountID: String
    public let environment: TradingEnvironment
    public let symbol: String
    public let lotRemainingQty: String
    public let createdAt: String
    public let expiresAt: String
    public let session: String?
    public let quote: ManualQuote?
    public let freshPrice: String?
    public let plan: ManualOrderPlan?
    public let checks: [ManualCheck]
    public let reasons: [String]
    public let factsSHA256: String
    public var id: String { request.previewID }

    enum CodingKeys: String, CodingKey {
        case request, environment, symbol, session, quote, plan, checks, reasons
        case brokerAccountID = "broker_account_id"
        case lotRemainingQty = "lot_remaining_qty"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case freshPrice = "fresh_price"
        case factsSHA256 = "facts_sha256"
    }
}

/// The owner's confirmation of one lot sale preview, under a stable command ID.
public struct LotSaleConfirmation: Codable, Equatable, Sendable {
    public let commandID: String
    public let previewID: String
    public let accountID: String
    public let actor: String

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

public struct LotSaleRecord: Codable, Equatable, Sendable {
    public let request: LotSaleConfirmation
    public let lotID: String
    public let confirmedAt: String
    public let state: String
    public let reason: String?
    public let clientID: String?

    enum CodingKeys: String, CodingKey {
        case request, state, reason
        case lotID = "lot_id"
        case confirmedAt = "confirmed_at"
        case clientID = "client_id"
    }
}

/// Where a confirmed lot sale stands: rejected before any order, or its order's latest state.
public struct LotSaleResult: Codable, Equatable, Sendable {
    public let sale: LotSaleRecord
    public let status: String
    public let reason: String?
    public let clientID: String?
    public let brokerOrderID: String?
    public let orderStatus: String?
    public let filledQty: String
    public let filledAvgPrice: String?

    enum CodingKeys: String, CodingKey {
        case sale, status, reason
        case clientID = "client_id"
        case brokerOrderID = "broker_order_id"
        case orderStatus = "order_status"
        case filledQty = "filled_qty"
        case filledAvgPrice = "filled_avg_price"
    }
}
