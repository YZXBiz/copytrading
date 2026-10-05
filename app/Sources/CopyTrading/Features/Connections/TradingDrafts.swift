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

    init(
        message: String = "", expectedAction: TradingInstructionAction = .buy,
        expectedSymbol: String = "AAPL", expectedFraction: String = ""
    ) {
        self.message = message
        self.expectedAction = expectedAction
        self.expectedSymbol = expectedSymbol
        self.expectedFraction = expectedFraction
    }

    init(example: TradingProfileExample) {
        self.init(
            message: example.message, expectedAction: example.expectedAction,
            expectedSymbol: example.expectedSymbol, expectedFraction: example.expectedFraction ?? ""
        )
    }
}

/// The one account a guru copies into (ADR-0007). Its maximum per stock is the guru's full
/// position, so the draft holds only the account and the share a call with no size buys.
struct TradingConnectionDraft: Identifiable {
    let id = UUID()
    var accountID: String
    var defaultFraction: String
    var useDefaultFraction: Bool

    /// A call that names no size buys the full position unless the owner lowers the default share
    /// or turns it off, which leaves such a call for the owner.
    init(accountID: String = "primary", defaultFraction: String? = "1") {
        self.accountID = accountID
        self.defaultFraction = defaultFraction ?? "1"
        self.useDefaultFraction = defaultFraction != nil
    }

    /// The saved connection: what the engine sizes from, and what the sizing example uses.
    func terms(fullPositionUSD: String) -> TradingRouteConnection {
        TradingRouteConnection(
            accountID: accountID.trimmed, fullPositionUSD: fullPositionUSD,
            defaultFraction: useDefaultFraction ? defaultFraction.trimmed : nil
        )
    }
}

struct TradingRouteDraft: Identifiable {
    let id = UUID()
    var channelID: String
    var authorID: String
    var guruID: String
    var displayName: String
    var prefix: String
    /// The owner's guidance for reading this guru, usually edited from a learned draft.
    var playbook: String
    var exitBasis: TradingExitBasis
    /// How many batches make the guru's full position; nil when the guru does not buy in batches.
    var batches: Int?
    var sellsReferTo: TradingSellsReferTo
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
        prefix: String = "ALERT:", playbook: String = "",
        exitBasis: TradingExitBasis = .originalPosition,
        batches: Int? = nil, sellsReferTo: TradingSellsReferTo = .buyPrice,
        examples: [TradingProfileExampleDraft] = [],
        connection: TradingConnectionDraft? = nil
    ) {
        self.channelID = channelID
        self.authorID = authorID
        self.guruID = guruID
        self.displayName = displayName
        self.prefix = prefix
        self.playbook = playbook
        self.exitBasis = exitBasis
        self.batches = batches
        self.sellsReferTo = sellsReferTo
        self.examples = examples
        self.connection = connection
    }
}
