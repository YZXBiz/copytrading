import DesktopCore
import Foundation

struct TradingAccountDraft: Identifiable {
    let id = UUID()
    var name: String
    var environment: TradingEnvironment
    var policy: TradingAccountPolicy
    var key = ""
    var secret = ""

    init(
        name: String = "primary", environment: TradingEnvironment = .paper,
        policy: TradingAccountPolicy = .init()
    ) {
        self.name = name
        self.environment = environment
        self.policy = policy
    }
}

struct TradingProfileExampleDraft: Identifiable {
    let id = UUID()
    var message: String
    var expectedAction: TradingInstructionAction
    var expectedSymbol: String
    var expectedFraction: String
    /// The guru's price in the post, and for a sell the buy price it names; empty when unchecked.
    var expectedPrice: String
    var expectedBuyPrice: String

    init(
        message: String = "", expectedAction: TradingInstructionAction = .buy,
        expectedSymbol: String = "AAPL", expectedFraction: String = "",
        expectedPrice: String = "", expectedBuyPrice: String = ""
    ) {
        self.message = message
        self.expectedAction = expectedAction
        self.expectedSymbol = expectedSymbol
        self.expectedFraction = expectedFraction
        self.expectedPrice = expectedPrice
        self.expectedBuyPrice = expectedBuyPrice
    }

    init(example: TradingProfileExample) {
        self.init(
            message: example.message, expectedAction: example.expectedAction,
            expectedSymbol: example.expectedSymbol, expectedFraction: example.expectedFraction ?? "",
            expectedPrice: example.expectedPrice ?? "", expectedBuyPrice: example.expectedBuyPrice ?? ""
        )
    }
}

/// The one account a guru copies into (ADR-0007). Its maximum per stock is the guru's full
/// position; a call that names no size asks for all of it, trimmed by the maximum per order
/// (ADR-0010).
struct TradingConnectionDraft: Identifiable {
    let id = UUID()
    var accountID: String

    init(accountID: String = "primary") {
        self.accountID = accountID
    }

    /// The saved connection: what the engine sizes from, and what the sizing example uses.
    func terms(fullPositionUSD: String) -> TradingRouteConnection {
        TradingRouteConnection(accountID: accountID.trimmed, fullPositionUSD: fullPositionUSD)
    }
}

struct TradingRouteDraft: Identifiable {
    let id = UUID()
    var channelID: String
    var authorID: String
    var guruID: String
    var displayName: String
    /// The owner's guidance for reading this guru, usually edited from a learned draft.
    var playbook: String
    /// Minutes within which the same call again is a re-post; nil copies every post.
    var repeatWindowMinutes: Int?
    var examples: [TradingProfileExampleDraft]
    /// The one account this guru copies into, once the owner has chosen it.
    var connection: TradingConnectionDraft?

    /// A new guru gets a stable ID of its own, so the owner only ever names them; renaming later
    /// keeps the ID and therefore the guru's history.
    static func newGuruID() -> String {
        "guru-\(UUID().uuidString.prefix(8).lowercased())"
    }

    init(
        channelID: String = "", authorID: String = "",
        guruID: String = TradingRouteDraft.newGuruID(), displayName: String = "",
        playbook: String = "",
        repeatWindowMinutes: Int? = TradingRouteConfiguration.defaultRepeatWindowMinutes,
        examples: [TradingProfileExampleDraft] = [],
        connection: TradingConnectionDraft? = nil
    ) {
        self.channelID = channelID
        self.authorID = authorID
        self.guruID = guruID
        self.displayName = displayName
        self.playbook = playbook
        self.repeatWindowMinutes = repeatWindowMinutes
        self.examples = examples
        self.connection = connection
    }
}
