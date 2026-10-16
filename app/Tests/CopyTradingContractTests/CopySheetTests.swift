import DesktopCore
import Foundation
import Testing

/// The copy sheet never shows one order and sends another: its footer and button spend what the
/// engine's plan spends after the account's max per order, and a post that names a price is
/// copied at that price, never at the market above it.
@MainActor
func runCopySheetTests() throws {
    try theFooterSpendsWhatTheCappedPlanSpends()
    try theFooterCountsSharesAtTheLimitTheEngineSends()
    try sizesTheMaxPerOrderMakesTheSameReadAsOne()
    try thePostsPriceIsTheDefault()
}

/// Zhao's "如果CCL跌到23.39我会买" into an account with a $250 max per order and a $1,000 full
/// position: the sheet chose "Full $250" but its footer said "Buy $1,000 of CCL".
@MainActor
private func theFooterSpendsWhatTheCappedPlanSpends() throws {
    let account = try fixtureAccount()
    let full = TradingRouteConnection(accountID: account.accountID, fullPositionUSD: "1000")
    let draft = ManualInstructionDraft(call: try call(#"{"action": "buy", "symbol": "CCL", "price": "23.39"}"#))
    let estimate = ManualOrderEstimate(
        drafts: [draft], accounts: [account], connections: [account.accountID: full],
        maxOrderUSD: [account.accountID: 250], mode: .copy)

    try #require(estimate.action == "Buy $250 of CCL", "the button: \(estimate.action)")
    let order = estimate.summary?.order
    try #require(order == "Buy $250 of CCL ≈ 10.688 shares at $23.39", "the footer: \(order ?? "nil")")
    // The same dollars the engine's plan spends, by the rule `sizing-examples.json` holds both to.
    try #require(estimate.budget(draft, in: account) == full.spentUSD(sourceFraction: nil, maxOrderUSD: 250))

    // Under the max per order nothing is cut.
    var sixth = draft
    sixth.fraction = "\(Decimal(1) / Decimal(6))"
    let small = ManualOrderEstimate(
        drafts: [sixth], accounts: [account], connections: [account.accountID: full],
        maxOrderUSD: [account.accountID: 250], mode: .copy)
    try #require(small.action == "Buy $166.66 of CCL", "a sixth: \(small.action)")
}

/// A conditional buy of CCL at $25.14 into an account with a $250 max per order that buys up to
/// 1% above the price. The footer once said "≈ 9.944 shares at $25.14" while the engine sent 9.846
/// shares with a $25.39 limit, as its checked row then said.
@MainActor
private func theFooterCountsSharesAtTheLimitTheEngineSends() throws {
    let account = try fixtureAccount()
    let full = TradingRouteConnection(accountID: account.accountID, fullPositionUSD: "1000")
    let draft = ManualInstructionDraft(call: try call(#"{"action": "buy", "symbol": "CCL", "price": "25.14"}"#))
    let estimate = ManualOrderEstimate(
        drafts: [draft], accounts: [account], connections: [account.accountID: full],
        maxOrderUSD: [account.accountID: 250], maxAbovePct: [account.accountID: 1], mode: .copy)

    let order = estimate.summary?.order
    try #require(order == "Buy $250 of CCL ≈ 9.846 shares at $25.39", "the footer: \(order ?? "nil")")
    // The engine's `limit_price`: down to a cent, to a hundredth of a cent under $1.
    try #require(ManualOrderEstimate.limit(Decimal(string: "25.14")!, abovePct: 1) == Decimal(string: "25.39")!)
    try #require(ManualOrderEstimate.limit(Decimal(string: "0.5123")!, abovePct: 1) == Decimal(string: "0.5174")!)
    try #require(ManualOrderEstimate.limit(Decimal(string: "23.39")!, abovePct: 0) == Decimal(string: "23.39")!)
}

private func sizesTheMaxPerOrderMakesTheSameReadAsOne() throws {
    let full = TradingRouteConnection(accountID: "paper", fullPositionUSD: "1000")
    let sixth = "\(Decimal(1) / Decimal(6))"
    let capped = BuySize.choices(fullPosition: full, maxOrderUSD: 250)
    try #require(capped.count == 2, "⅙ and ¼ or more: \(capped)")
    try #require(capped[0] == BuySize(shares: [sixth], usd: Decimal(string: "166.66"), isCapped: false))
    try #require(capped[1].shares == ["0.25", "\(Decimal(1) / Decimal(3))", "0.5", ""] && capped[1].usd == 250)
    // The full position, which the post asked for by naming no size, is one of them.
    try #require(capped[1].contains("") && !capped[0].contains(""))

    let roomy = BuySize.choices(fullPosition: full, maxOrderUSD: 5000)
    try #require(roomy.map(\.usd) == [Decimal(string: "166.66"), 250, Decimal(string: "333.33"), 500, 1000])
    try #require(BuySize.choices(fullPosition: full, maxOrderUSD: 100).map(\.shares.count) == [5])
    // Several accounts: no dollars, every size.
    try #require(BuySize.choices(fullPosition: nil, maxOrderUSD: nil).count == 5)
}

private func thePostsPriceIsTheDefault() throws {
    let conditional = ManualInstructionDraft(call: try call(#"{"action": "buy", "symbol": "CCL", "price": "23.39"}"#))
    try #require(conditional.priceChoice == .guru && conditional.price == "23.39", "the guru's price leads")
    try #require(conditional.value.price == "23.39", "sent as a limit at the guru's price")

    // A buy that names no price follows the market, which fills its price only from a live quote.
    let unpriced = ManualInstructionDraft(call: try call(#"{"action": "buy", "symbol": "WMT", "price": null}"#))
    try #require(unpriced.priceChoice == .market && unpriced.price.isEmpty && !unpriced.isValid)

    let guessed = try #require(ManualInstructionGuess.draft(from: "buy wmt 1/6 110", held: []))
    try #require(guessed.priceChoice == .guru && guessed.price == "110")
    let sell = try #require(ManualInstructionGuess.draft(from: "sell wmt half", held: ["WMT"]))
    try #require(sell.priceChoice == .market && sell.sellsAtMarket)
}

private func call(_ json: String) throws -> SourceInstruction {
    try JSONDecoder().decode(SourceInstruction.self, from: Data(json.utf8))
}

private func fixtureAccount() throws -> AccountOverview {
    let contracts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Resources/Contracts")
    let response = try JSONDecoder().decode(
        EngineResponse.self, from: Data(contentsOf: contracts.appending(path: "account-overviews-response.json")))
    guard case .accounts(let page) = try response.successValue(), let account = page.items.first else {
        struct NoAccount: Error {}
        throw NoAccount()
    }
    return account
}
