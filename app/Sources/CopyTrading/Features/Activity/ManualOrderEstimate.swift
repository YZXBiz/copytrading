import DesktopCore
import Foundation

/// What the drafted trades would place, worked out in the app before the engine checks them: the
/// one-line preview under the choices and the words on the sheet's button. The engine's preview
/// decides the real quantity and limit; this only says what the owner is asking for.
struct ManualOrderEstimate {
    let drafts: [ManualInstructionDraft]
    /// The chosen accounts, in the order the sheet lists them.
    let accounts: [AccountOverview]
    /// This guru's full position in each account, by account.
    let connections: [String: TradingRouteConnection]
    let mode: ManualReviewMode

    /// The order as one line, "Sell 0.442 WMT ≈ $48.70", and the accounts it goes to, "primary ·
    /// Paper"; nil until a whole trade and an account are chosen.
    @MainActor var summary: (order: String, place: String)? {
        let valid = drafts.filter(\.isValid)
        guard let draft = valid.first, let account = accounts.first else { return nil }
        var order = phrase(draft, in: account)
        if valid.count > 1 { order = L10n.string("%@ and %lld more", order, Int64(valid.count - 1)) }
        let place = accounts.map { L10n.string("%@ · %@", $0.accountID, L10n.string($0.environment == .live ? "Live" : "Paper")) }
        return (order, place.joined(separator: "   "))
    }

    /// The button: "Sell 0.442 WMT", "Buy $100 of WMT", "Approve", or "Copy".
    @MainActor var action: String {
        if mode == .approve { return L10n.string("Approve") }
        guard drafts.count == 1, let draft = drafts.first, !draft.symbol.trimmed.isEmpty else {
            return L10n.string("Copy Calls")
        }
        let symbol = draft.symbol.trimmed.uppercased()
        if accounts.count == 1, let account = accounts.first {
            if draft.isSell, let shares = shares(draft, in: account), shares > 0 {
                return L10n.string("Sell %@ %@", Self.count(shares), symbol)
            }
            if !draft.isSell, let budget = budget(draft, in: account) {
                return L10n.string("Buy %@ of %@", Humanize.dollars("\(budget)"), symbol)
            }
        }
        return L10n.string(draft.isSell ? "Sell %@" : "Buy %@", symbol)
    }

    @MainActor private func phrase(_ draft: ManualInstructionDraft, in account: AccountOverview) -> String {
        let symbol = draft.symbol.trimmed.uppercased()
        let price = Decimal(string: draft.price.trimmed)
        if draft.isSell {
            guard let shares = shares(draft, in: account) else {
                return L10n.string("No %@ that CopyTrading bought is held", symbol)
            }
            guard let value = (currentPrice(symbol, in: account) ?? price).map({ Humanize.usd($0 * shares) }) else {
                return L10n.string("Sell %@ %@", Self.count(shares), symbol)
            }
            return L10n.string("Sell %@ %@ ≈ %@", Self.count(shares), symbol, value)
        }
        let at = price.map(Humanize.usd) ?? "—"
        guard let budget = budget(draft, in: account) else { return L10n.string("Buy %@ at %@", symbol, at) }
        return L10n.string("Buy %@ of %@ at %@", Humanize.dollars("\(budget)"), symbol, at)
    }

    /// Shares to three places at most, as an order reads them: "0.442", "12".
    static func count(_ shares: Decimal) -> String {
        shares.formatted(.number.precision(.fractionLength(0...3)))
    }

    /// A sell's share of what CopyTrading holds of the stock in the account, before rounding to
    /// what the broker allows; nil when it holds none.
    func shares(_ draft: ManualInstructionDraft, in account: AccountOverview) -> Decimal? {
        let symbol = draft.symbol.trimmed.uppercased()
        guard let position = account.positions.first(where: { $0.symbol.uppercased() == symbol }),
            let owned = Decimal(string: position.ownedQty), owned > 0,
            let fraction = Decimal(string: draft.fraction.trimmed)
        else { return nil }
        var shares = owned * min(fraction, 1)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &shares, 6, .down)
        return rounded
    }

    func budget(_ draft: ManualInstructionDraft, in account: AccountOverview) -> Decimal? {
        connections[account.accountID]?.copiedBudgetUSD(sourceFraction: Decimal(string: draft.fraction.trimmed))
    }

    private func currentPrice(_ symbol: String, in account: AccountOverview) -> Decimal? {
        account.positions.first { $0.symbol.uppercased() == symbol }?.currentPrice.flatMap { Decimal(string: $0) }
    }
}
