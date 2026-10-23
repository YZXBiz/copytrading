import DesktopCore
import Foundation

/// What the drafted trades would place: the one-line preview under the choices and the words on the
/// sheet's button. Before the engine checks a buy, it is "up to" the guru's share of the full
/// position cut to the account's largest single buy, since the per-stock and total limits, which only
/// the engine checks, may cut it further; once the engine's check answers, it is the dollars that
/// check plans. Shares are counted at the order's limit: the price plus the account's allowance
/// above it, as the engine's `limit_price` sets it.
struct ManualOrderEstimate {
    let drafts: [ManualInstructionDraft]
    /// The chosen accounts, in the order the sheet lists them.
    let accounts: [AccountOverview]
    /// This guru's full position in each account, by account.
    let connections: [String: TradingRouteConnection]
    /// Each account's largest single buy, by account: no one buy spends more.
    let maxOrderUSD: [String: Decimal]
    /// How far above the price each account's buy limit sits, in percent, by account.
    var maxAbovePct: [String: Decimal] = [:]
    let mode: ManualReviewMode
    /// The broker's latest quote for each stock, by symbol: a sell is valued at the bid, and a buy
    /// at the market is counted in shares at the ask.
    var quotes: [String: LiveQuote] = [:]
    /// The dollars the engine's check plans for each buy, by "account:index", once it has answered.
    var planned: [String: Decimal] = [:]

    /// The order as one line, "Sell 0.442 WMT ≈ $48.70" or "Buy up to $1,000 of AAPL ≈ 4.414 shares at
    /// $226.56", and the accounts it goes to, "primary ·
    /// Paper"; nil until a whole trade and an account are chosen.
    @MainActor var summary: (order: String, place: String)? {
        let valid = drafts.filter(\.isValid)
        guard let index = drafts.firstIndex(where: \.isValid), let account = accounts.first else { return nil }
        var order = phrase(drafts[index], at: index, in: account)
        if valid.count > 1 { order = L10n.string("%@ and %lld more", order, Int64(valid.count - 1)) }
        let place = accounts.map { L10n.string("%@ · %@", $0.accountID, L10n.string($0.environment == .live ? "Live" : "Paper")) }
        return (order, place.joined(separator: "   "))
    }

    /// The button: "Sell 0.442 WMT", "Buy up to $100 of WMT" ("Buy $100 of WMT" once the engine has
    /// checked it), "Approve", or "Copy".
    @MainActor var action: String {
        if mode == .approve { return L10n.string("Approve") }
        guard drafts.count == 1, let draft = drafts.first else { return L10n.string("Copy Calls") }
        // No stock chosen yet: the button still names the side, so it never reads as something else.
        guard !draft.symbol.trimmed.isEmpty else { return L10n.string(draft.isSell ? "Sell" : "Buy") }
        let symbol = draft.symbol.trimmed.uppercased()
        if accounts.count == 1, let account = accounts.first {
            if draft.isSell, let shares = shares(draft, in: account), shares > 0 {
                return L10n.string("Sell %@ %@", Self.count(shares), symbol)
            }
            if !draft.isSell, let planned = planned["\(account.accountID):0"] {
                return L10n.string("Buy %@ of %@", Humanize.dollars("\(planned)"), symbol)
            }
            if !draft.isSell, let budget = budget(draft, in: account) {
                return L10n.string("Buy up to %@ of %@", Humanize.dollars("\(budget)"), symbol)
            }
        }
        return L10n.string(draft.isSell ? "Sell %@" : "Buy %@", symbol)
    }

    @MainActor private func phrase(_ draft: ManualInstructionDraft, at index: Int, in account: AccountOverview) -> String {
        let symbol = draft.symbol.trimmed.uppercased()
        let price = Decimal(string: draft.price.trimmed)
        if draft.isSell {
            guard let shares = shares(draft, in: account) else {
                return L10n.string("No %@ that CopyTrading bought is held", symbol)
            }
            let bid = quotes[symbol]?.bid ?? currentPrice(symbol, in: account) ?? price
            guard let value = bid.map({ Humanize.usd($0 * shares) }) else {
                return L10n.string("Sell %@ %@", Self.count(shares), symbol)
            }
            return L10n.string("Sell %@ %@ ≈ %@", Self.count(shares), symbol, value)
        }
        let ask = price ?? quotes[symbol]?.ask
        let at = ask.map(Humanize.usd) ?? "—"
        let checked = planned["\(account.accountID):\(index)"]
        guard let budget = checked ?? budget(draft, in: account) else { return L10n.string("Buy %@ at %@", symbol, at) }
        let dollars = Humanize.dollars("\(budget)")
        guard let ask else {
            return checked != nil
                ? L10n.string("Buy %@ of %@ at %@", dollars, symbol, at)
                : L10n.string("Buy up to %@ of %@ at %@", dollars, symbol, at)
        }
        let limit = Self.limit(ask, abovePct: maxAbovePct[account.accountID] ?? 0)
        // The sentence says the count is an estimate; the count never adds a second "≈".
        let shares = Humanize.shares(budget / limit, of: symbol, marksRounding: false)
        return checked != nil
            ? L10n.string("Buy %@ of %@ ≈ %@ at %@", dollars, symbol, shares, Humanize.usd(limit))
            : L10n.string("Buy up to %@ of %@ ≈ %@ at %@", dollars, symbol, shares, Humanize.usd(limit))
    }

    /// A buy's limit as the engine sets it: the price plus the allowance, down to a cent (a
    /// hundredth of a cent under $1).
    static func limit(_ price: Decimal, abovePct: Decimal) -> Decimal {
        var ceiling = price * (1 + abovePct / 100)
        var limit = Decimal()
        NSDecimalRound(&limit, &ceiling, ceiling >= 1 ? 2 : 4, .down)
        return limit
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

    /// What a buy spends in the account, as the engine's `entry_budget` cuts it: its share of the
    /// full position, then no more than the largest single buy.
    func budget(_ draft: ManualInstructionDraft, in account: AccountOverview) -> Decimal? {
        connections[account.accountID]?.spentUSD(
            sourceFraction: Decimal(string: draft.fraction.trimmed),
            sourceUSD: draft.isSell ? nil : Decimal(string: draft.usdAmount.trimmed),
            maxOrderUSD: maxOrderUSD[account.accountID]
        )
    }

    private func currentPrice(_ symbol: String, in account: AccountOverview) -> Decimal? {
        account.positions.first { $0.symbol.uppercased() == symbol }?.currentPrice.flatMap { Decimal(string: $0) }
    }
}
