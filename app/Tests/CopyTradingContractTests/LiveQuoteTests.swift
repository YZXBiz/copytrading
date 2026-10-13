import DesktopCore
import Foundation
import Testing

/// The trade sheet prices a typed stock from the broker's live quote: a buy at the ask, a sell at
/// the bid, always saying when it was quoted, and plainly when the broker has none. The order line
/// under the choices counts and values the trade from the same quote.
@MainActor
func runLiveQuoteTests() throws {
    let utc = try #require(TimeZone(identifier: "UTC"))
    let english = Locale(identifier: "en_US")
    let quotedAt = try #require(Humanize.date("2026-09-26T15:53:20Z"))
    let live = LiveQuote(
        symbol: "AAPL", quote: MarketQuote(feed: "iex", bid: "226.5", ask: "226.56", timestamp: "2026-09-26T15:53:20Z"))

    try #require(live.price(isSell: false) == Decimal(string: "226.56") && live.price(isSell: true) == Decimal(string: "226.5"))
    let fresh = live.detail(isSell: false, now: quotedAt.addingTimeInterval(5), zone: utc, locale: english)
    try #require(fresh == "≈ $226.56 · as of 3:53:20\u{202F}PM", "a fresh quote's time: \(fresh)")
    let bid = live.detail(isSell: true, now: quotedAt.addingTimeInterval(5), zone: utc, locale: english)
    try #require(bid.hasPrefix("≈ $226.50 · as of"), "a sell is priced at the bid: \(bid)")
    let stale = live.detail(isSell: false, now: quotedAt.addingTimeInterval(190), zone: utc, locale: english)
    try #require(stale == "≈ $226.56 · 3 min old", "an old quote says its age: \(stale)")
    try #require(live.when(now: quotedAt.addingTimeInterval(2 * 3600), zone: utc, locale: english) == "2 hr old")

    let missing = LiveQuote(symbol: "ZZZZ", quote: nil)
    try #require(missing.price(isSell: false) == nil && missing.detail(isSell: false) == "No quote for ZZZZ")
    let oneSided = LiveQuote(symbol: "F", quote: MarketQuote(feed: "overnight", bid: "0", ask: "10.02", timestamp: nil))
    try #require(oneSided.price(isSell: true) == Decimal(string: "10.02") && oneSided.detail(isSell: true) == "≈ $10.02")
    try #require(LiveQuote.canQuote("BRK.B") && !LiveQuote.canQuote("") && !LiveQuote.canQuote("aapl"))

    try anEstimateUsesTheLiveQuote()
}

@MainActor
private func anEstimateUsesTheLiveQuote() throws {
    let contracts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Resources/Contracts")
    let response = try JSONDecoder().decode(
        EngineResponse.self, from: Data(contentsOf: contracts.appending(path: "account-overviews-response.json")))
    guard case .accounts(let page) = try response.successValue(), let account = page.items.first else {
        struct NoAccount: Error {}
        throw NoAccount()
    }
    let connections = ["paper": TradingRouteConnection(accountID: "paper", fullPositionUSD: "1000")]

    // ABC is held (2 shares) with no last price: only the live bid can value a sale of half.
    var sell = ManualInstructionDraft()
    sell.isSell = true
    sell.symbol = "ABC"
    sell.fraction = "0.5"
    let unquoted = ManualOrderEstimate(drafts: [sell], accounts: [account], connections: connections, mode: .enter)
    try #require(unquoted.summary?.order == "Sell 1 ABC", "a sale with no price: \(unquoted.summary?.order ?? "nil")")
    let abc = LiveQuote(symbol: "ABC", quote: MarketQuote(feed: "iex", bid: "10.5", ask: "10.6", timestamp: nil))
    let quoted = ManualOrderEstimate(
        drafts: [sell], accounts: [account], connections: connections, mode: .enter, quotes: ["ABC": abc])
    try #require(quoted.summary?.order == "Sell 1 ABC ≈ $10.50", "a sale at the bid: \(quoted.summary?.order ?? "nil")")

    // A full-position buy at the market's ask is counted in shares at that ask.
    var buy = ManualInstructionDraft()
    buy.symbol = "XYZ"
    buy.price = "250"
    let xyz = LiveQuote(symbol: "XYZ", quote: MarketQuote(feed: "iex", bid: "249.9", ask: "250", timestamp: nil))
    let buying = ManualOrderEstimate(
        drafts: [buy], accounts: [account], connections: connections, mode: .enter, quotes: ["XYZ": xyz])
    try #require(
        buying.summary?.order == "Buy $1,000 of XYZ ≈ 4 shares at $250.00",
        "a dollar budget in shares: \(buying.summary?.order ?? "nil")")

    // A count that doesn't come out even still says "≈" once.
    buy.price = "300"
    let uneven = ManualOrderEstimate(
        drafts: [buy], accounts: [account], connections: connections, mode: .enter,
        quotes: ["XYZ": LiveQuote(symbol: "XYZ", quote: MarketQuote(feed: "iex", bid: "299", ask: "300", timestamp: nil))])
    try #require(
        uneven.summary?.order == "Buy $1,000 of XYZ ≈ 3.333 shares at $300.00",
        "an uneven count: \(uneven.summary?.order ?? "nil")")
}
