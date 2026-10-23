import DesktopCore
import Foundation

struct TradingAccountDraft: Identifiable {
    let id = UUID()
    var name: String
    var environment: TradingEnvironment
    var policy: TradingAccountPolicy
    var key = ""
    var secret = ""
    /// The name the account is saved under, so a rename can be undone; nil for a new account.
    let savedName: String?

    init(
        name: String = "primary", environment: TradingEnvironment = .paper,
        policy: TradingAccountPolicy = .init(), savedName: String? = nil
    ) {
        self.name = name
        self.environment = environment
        self.policy = policy
        self.savedName = savedName
    }

    /// Why the engine would refuse the name, in the owner's words; nil when it is fine.
    var nameProblem: String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give the account a name." }
        guard name.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) == nil else { return nil }
        return name.count > 64
            ? "Keep the name to 64 characters."
            : "Use only letters, digits, “-” and “_” in the name: no spaces."
    }
}

/// The one account a guru copies into (ADR-0007), and the guru's full position in it: what the
/// guru's whole position is in dollars, so a 1/6 call buys a sixth of it (ADR-0010). Empty uses the
/// account's maximum per stock, which also caps what is bought.
struct TradingConnectionDraft: Identifiable {
    let id = UUID()
    var accountID: String
    var fullPositionUSD: String

    init(accountID: String = "primary", fullPositionUSD: String = "") {
        self.accountID = accountID
        self.fullPositionUSD = fullPositionUSD
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
    var displayName: String
    /// The owner's guidance for reading this guru, usually edited from a learned draft.
    var playbook: String
    /// Minutes within which the same call again is a re-post; nil copies every post.
    var repeatWindowMinutes: Int?
    /// The one account this guru copies into, once the owner has chosen it.
    var connection: TradingConnectionDraft?

    init(
        channelID: String = "", authorID: String = "",
        displayName: String = "",
        playbook: String = "",
        repeatWindowMinutes: Int? = TradingRouteConfiguration.defaultRepeatWindowMinutes,
        connection: TradingConnectionDraft? = nil
    ) {
        self.channelID = channelID
        self.authorID = authorID
        self.displayName = displayName
        self.playbook = playbook
        self.repeatWindowMinutes = repeatWindowMinutes
        self.connection = connection
    }
}
