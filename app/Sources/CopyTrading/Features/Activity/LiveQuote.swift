import DesktopCore
import Foundation

/// A stock's latest quote from the account's broker, asked for as the owner types a ticker in the
/// trade sheet: a buy pays the ask, a sell gets the bid, and the price always says when it was
/// quoted.
struct LiveQuote: Equatable {
    /// Tickers the engine can quote: a letter, then letters, digits, or a dot.
    static func canQuote(_ symbol: String) -> Bool {
        symbol.wholeMatch(of: /[A-Z][A-Z0-9.]{0,9}/) != nil
    }

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

    /// "≈ $226.56 · as of 11:53:20 AM" beside Market, or "No quote for XYZ".
    @MainActor
    func detail(isSell: Bool, now: Date = .now, zone: TimeZone? = nil, locale: Locale? = nil) -> String {
        guard let price = price(isSell: isSell) else { return L10n.string("No quote for %@", symbol) }
        let near = L10n.string("≈ %@", Humanize.usd(price))
        guard let when = when(now: now, zone: zone, locale: locale) else { return near }
        return L10n.string("%@ · %@", near, when)
    }

    /// When it was quoted: the clock within a minute, then its age said plainly, and the day once
    /// it is a day old.
    @MainActor
    func when(now: Date = .now, zone: TimeZone? = nil, locale: Locale? = nil) -> String? {
        guard let quotedAt else { return nil }
        let minutes = Int(now.timeIntervalSince(quotedAt) / 60)
        if minutes < 1 {
            let clock = quotedAt.formatted(AppTime.style(.dateTime.hour().minute().second(), zone: zone, locale: locale))
            return L10n.string("as of %@", clock)
        }
        if minutes < 60 { return L10n.string("%lld min old", Int64(minutes)) }
        if minutes < 24 * 60 { return L10n.string("%lld hr old", Int64(minutes / 60)) }
        let day = quotedAt.formatted(
            AppTime.style(.dateTime.month(.abbreviated).day().hour().minute(), zone: zone, locale: locale))
        return L10n.string("as of %@", day)
    }

    private static func positive(_ text: String?) -> Decimal? {
        text.flatMap { Decimal(string: $0) }.flatMap { $0 > 0 ? $0 : nil }
    }
}
