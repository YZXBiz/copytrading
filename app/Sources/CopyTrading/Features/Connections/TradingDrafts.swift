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

struct TradingConnectionDraft: Identifiable {
    let id = UUID()
    var accountID: String
    var mode: TradingSizingMode
    var amountUSD: String
    var defaultFraction: String
    var useDefaultFraction: Bool

    /// Every call buys the guru's share of a full position, which is the account's maximum per
    /// stock; a call that names no size buys the default share, 1/6 unless the owner changes it.
    init(
        accountID: String = "primary", mode: TradingSizingMode = .proportional,
        amountUSD: String = "", defaultFraction: String? = "\(Decimal(1) / Decimal(6))"
    ) {
        self.accountID = accountID
        self.mode = mode
        self.amountUSD = amountUSD
        self.defaultFraction = defaultFraction ?? "\(Decimal(1) / Decimal(6))"
        self.useDefaultFraction = defaultFraction != nil
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
    var examples: [TradingProfileExampleDraft]
    var connections: [TradingConnectionDraft]

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
        examples: [TradingProfileExampleDraft] = [],
        connections: [TradingConnectionDraft] = []
    ) {
        self.channelID = channelID
        self.authorID = authorID
        self.guruID = guruID
        self.displayName = displayName
        self.prefix = prefix
        self.playbook = playbook
        self.exitBasis = exitBasis
        self.examples = examples
        self.connections = connections
    }
}
