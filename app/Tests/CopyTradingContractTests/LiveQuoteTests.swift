import DesktopCore
import Foundation
import Testing

/// The trade sheet prices a typed stock from the broker's live quote: a buy at the ask, a sell at
/// the bid, saying by the clock when it was quoted, and plainly when the broker has none or only an
/// old one. The order line under the choices counts and values the trade from the same quote.
@MainActor
func runLiveQuoteTests() throws {
    let utc = try #require(TimeZone(identifier: "UTC"))
    let english = Locale(identifier: "en_US")
    let quotedAt = try #require(Humanize.date("2026-09-26T15:53:20Z"))
    let live = LiveQuote(
        symbol: "AAPL", quote: MarketQuote(feed: "iex", bid: "226.5", ask: "226.56", timestamp: "2026-09-26T15:53:20Z"))

    try #require(live.price(isSell: false) == Decimal(string: "226.56") && live.price(isSell: true) == Decimal(string: "226.5"))
    let fresh = live.detail(isSell: false, now: quotedAt.addingTimeInterval(5), zone: utc, locale: english)
    try #require(fresh == "≈ $226.56 · 3:53\u{202F}PM", "a live quote's clock time: \(String(describing: fresh))")
    let bid = live.detail(isSell: true, now: quotedAt.addingTimeInterval(5), zone: utc, locale: english)
    try #require(bid?.hasPrefix("≈ $226.50 · ") == true, "a sell is priced at the bid: \(String(describing: bid))")
    try #require(live.problem(isSell: false, now: quotedAt.addingTimeInterval(5)) == nil)

    // An hour-old quote is not the market: Market offers no price and the row says why.
    let hourLater = quotedAt.addingTimeInterval(3600)
    try #require(!live.isLive(now: hourLater) && live.livePrice(isSell: false, now: hourLater) == nil)
    try #require(live.detail(isSell: false, now: hourLater, zone: utc, locale: english) == nil)
    let stale = live.problem(isSell: false, now: hourLater, zone: utc, locale: english)
    try #require(stale == "No live quote for AAPL since 3:53\u{202F}PM", "an old quote says so: \(String(describing: stale))")
    let yesterday = live.when(now: quotedAt.addingTimeInterval(24 * 3600), zone: utc, locale: english)
    try #require(yesterday == "Sep 26 at 3:53\u{202F}PM", "an older quote names its day: \(String(describing: yesterday))")

    let missing = LiveQuote(symbol: "ZZZZ", quote: nil)
    try #require(missing.price(isSell: false) == nil && missing.detail(isSell: false) == nil)
    try #require(missing.problem(isSell: false) == "No quote for ZZZZ")
    // A quote with no time can't be shown to be the market now.
    let untimed = LiveQuote(symbol: "F", quote: MarketQuote(feed: "overnight", bid: "0", ask: "10.02", timestamp: nil))
    try #require(untimed.price(isSell: true) == Decimal(string: "10.02") && !untimed.isLive())
    try #require(untimed.problem(isSell: true) == "No live quote for F")
    try #require(LiveQuote.canQuote("BRK.B") && !LiveQuote.canQuote("") && !LiveQuote.canQuote("aapl"))
    // A coin is quoted by its dollar pair, at any hour.
    try #require(LiveQuote.canQuote("BTC/USD") && !LiveQuote.canQuote("BTC/EUR") && !LiveQuote.canQuote("btc/usd"))
    try #require(Humanize.shares(Decimal(string: "0.001231481")!, of: "BTC/USD") == "0.001231481 BTC")
    try #require(Humanize.sharesOf(Decimal(string: "0.001231481")!, symbol: "BTC/USD") == "0.001231481")
    try #require(Humanize.shares(Decimal(string: "2.985")!, of: "PM") == "2.985 shares")

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
    let unquoted = ManualOrderEstimate(drafts: [sell], accounts: [account], connections: connections, maxOrderUSD: [:], mode: .enter)
    try #require(unquoted.summary?.order == "Sell 1 ABC", "a sale with no price: \(unquoted.summary?.order ?? "nil")")
    let abc = LiveQuote(symbol: "ABC", quote: MarketQuote(feed: "iex", bid: "10.5", ask: "10.6", timestamp: nil))
    let quoted = ManualOrderEstimate(
        drafts: [sell], accounts: [account], connections: connections, maxOrderUSD: [:], mode: .enter, quotes: ["ABC": abc])
    try #require(quoted.summary?.order == "Sell 1 ABC ≈ $10.50", "a sale at the bid: \(quoted.summary?.order ?? "nil")")

    // A full-position buy at the market's ask is counted in shares at that ask.
    var buy = ManualInstructionDraft()
    buy.symbol = "XYZ"
    buy.price = "250"
    buy.fraction = "1"
    let xyz = LiveQuote(symbol: "XYZ", quote: MarketQuote(feed: "iex", bid: "249.9", ask: "250", timestamp: nil))
    let buying = ManualOrderEstimate(
        drafts: [buy], accounts: [account], connections: connections, maxOrderUSD: [:], mode: .enter, quotes: ["XYZ": xyz])
    try #require(
        buying.summary?.order == "Buy up to $1,000 of XYZ ≈ 4 shares at $250.00",
        "a dollar budget in shares: \(buying.summary?.order ?? "nil")")

    // A count that doesn't come out even still says "≈" once.
    buy.price = "300"
    let uneven = ManualOrderEstimate(
        drafts: [buy], accounts: [account], connections: connections, maxOrderUSD: [:], mode: .enter,
        quotes: ["XYZ": LiveQuote(symbol: "XYZ", quote: MarketQuote(feed: "iex", bid: "299", ask: "300", timestamp: nil))])
    try #require(
        uneven.summary?.order == "Buy up to $1,000 of XYZ ≈ 3.333 shares at $300.00",
        "an uneven count: \(uneven.summary?.order ?? "nil")")
}
