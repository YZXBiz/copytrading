import DesktopCore
import Foundation

/// A stock's latest quote from the account's broker, asked for as the trade sheet opens, again
/// while it stays open, and as the owner types a ticker: a buy pays the ask, a sell gets the bid.
/// The price always says when it was quoted, and a quote too old to be the market now says so.
struct LiveQuote: Equatable {
    /// Tickers the engine can quote: a letter, then letters, digits, or a dot.
    static func canQuote(_ symbol: String) -> Bool {
        symbol.wholeMatch(of: /[A-Z][A-Z0-9.]{0,9}/) != nil
    }

    /// How long a quote stands for the market. The sheet asks again well within it; the engine's
    /// preview reads its own, fresher still, before anything is placed.
    static let liveFor: TimeInterval = 120

    let symbol: String
    /// Nil when the broker has no quote for the symbol.
    let quote: MarketQuote?

    var bid: Decimal? { Self.positive(quote?.bid) }
    var ask: Decimal? { Self.positive(quote?.ask) }
    var quotedAt: Date? { Humanize.date(quote?.timestamp) }

    /// What a buy pays or a sell gets, from the other side when the book has only one.
    func price(isSell: Bool) -> Decimal? {
        isSell ? bid ?? ask : ask ?? bid
    }

    /// Quoted within `liveFor` of `now`; a quote with no time is never live.
    func isLive(now: Date = .now) -> Bool {
        guard let quotedAt else { return false }
        let age = now.timeIntervalSince(quotedAt)
        return age > -5 && age <= Self.liveFor
    }

    /// The price, only while the quote is live: the market a buy at the market pays.
    func livePrice(isSell: Bool, now: Date = .now) -> Decimal? {
        isLive(now: now) ? price(isSell: isSell) : nil
    }

    /// "≈ $226.56 · 11:53 AM" beside Market while the quote is live; nil otherwise.
    @MainActor
    func detail(isSell: Bool, now: Date = .now, zone: TimeZone? = nil, locale: Locale? = nil) -> String? {
        guard let price = livePrice(isSell: isSell, now: now), let when = when(now: now, zone: zone, locale: locale) else {
            return nil
        }
        return L10n.string("%@ · %@", L10n.string("≈ %@", Humanize.usd(price)), when)
    }

    /// Why there is no market price, said plainly: "No quote for XYZ", or "No live quote for CCL
    /// since 7:19 AM" when the broker's latest is old. Nil while the quote is live.
    @MainActor
    func problem(isSell: Bool, now: Date = .now, zone: TimeZone? = nil, locale: Locale? = nil) -> String? {
        guard price(isSell: isSell) != nil else { return L10n.string("No quote for %@", symbol) }
        guard !isLive(now: now) else { return nil }
        guard let when = when(now: now, zone: zone, locale: locale) else { return L10n.string("No live quote for %@", symbol) }
        return L10n.string("No live quote for %@ since %@", symbol, when)
    }

    /// When it was quoted, by the clock: "8:19 AM" today, "Oct 14, 7:19 PM" before.
    @MainActor
    func when(now: Date = .now, zone: TimeZone? = nil, locale: Locale? = nil) -> String? {
        guard let quotedAt else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone ?? AppTime.zone
        if calendar.isDate(quotedAt, inSameDayAs: now) {
            return quotedAt.formatted(AppTime.style(.dateTime.hour().minute(), zone: zone, locale: locale))
        }
        return quotedAt.formatted(
            AppTime.style(.dateTime.month(.abbreviated).day().hour().minute(), zone: zone, locale: locale))
    }

    private static func positive(_ text: String?) -> Decimal? {
        text.flatMap { Decimal(string: $0) }.flatMap { $0 > 0 ? $0 : nil }
    }
}
