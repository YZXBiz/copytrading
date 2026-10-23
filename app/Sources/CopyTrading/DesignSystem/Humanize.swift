import Foundation

extension AppLanguage {
    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

/// Turns engine wire values (snake_case codes, ISO timestamps, decimal strings) into readable text.
enum Humanize {
    /// "review_required" becomes "Review required".
    static func code(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let spaced = raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        if let date = try? Date(iso, strategy: .iso8601) { return date }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? fractional.parse(iso)
    }

    /// A short absolute time, e.g. "Sep 28, 1:19 PM"; the raw value is kept when it cannot be parsed.
    @MainActor
    static func timestamp(_ iso: String?) -> String {
        guard let iso else { return "—" }
        guard let date = date(iso) else { return iso }
        return timestamp(date)
    }

    @MainActor
    static func timestamp(_ date: Date) -> String {
        date.formatted(AppTime.style(.dateTime.month(.abbreviated).day().hour().minute()))
    }

    /// A post's time to the second, e.g. "Oct 8, 8:58:12 AM": calls arrive seconds apart.
    @MainActor
    static func postTime(_ iso: String?) -> String {
        guard let iso else { return "—" }
        guard let date = date(iso) else { return iso }
        return postTime(date)
    }

    @MainActor
    static func postTime(_ date: Date) -> String {
        date.formatted(AppTime.style(.dateTime.month(.abbreviated).day().hour().minute().second()))
    }

    /// A feed row's time: the clock for today, the day and clock before that.
    @MainActor
    static func feedTime(_ iso: String?, now: Date = .now) -> String {
        guard let date = date(iso) else { return iso ?? "—" }
        return AppTime.calendar.isDate(date, inSameDayAs: now)
            ? date.formatted(AppTime.style(.dateTime.hour().minute().second()))
            : date.formatted(AppTime.style(.dateTime.month(.abbreviated).day().hour().minute()))
    }

    /// "2 min. ago" style text for recent events.
    @MainActor
    static func relative(_ iso: String?, now: Date = .now) -> String {
        guard let date = date(iso) else { return iso ?? "—" }
        return date.formatted(
            .relative(presentation: .named, unitsStyle: .abbreviated)
                .locale(AppLanguagePreference.shared.language.locale)
        )
    }

    /// "1 account", "2 accounts" for String contexts where Text inflection is unavailable.
    @MainActor
    static func count(_ value: Int, _ singular: String, plural: String? = nil) -> String {
        let quantity = value.formatted()
        let noun = value == 1 ? singular : plural ?? singular + "s"
        return L10n.string("%@ %@", quantity, L10n.string(noun))
    }

    /// Parts joined as one phrase with the language's own comma.
    @MainActor
    static func joined(_ parts: [String]) -> String {
        parts.joined(separator: L10n.string(", "))
    }

    /// Exact engine fractions such as "0.1666666666666666666666666667" read as "1/6".
    static func fraction(_ value: String) -> String {
        guard let decimal = Decimal(string: value) else { return value }
        let number = NSDecimalNumber(decimal: decimal).doubleValue
        for denominator in 1...100 {
            let numerator = (number * Double(denominator)).rounded()
            if numerator > 0, abs(numerator / Double(denominator) - number) < 1e-9 {
                return denominator == 1 ? "\(Int(numerator))" : "\(Int(numerator))/\(denominator)"
            }
        }
        return number.formatted(.number.precision(.significantDigits(1...4)))
    }

    static func usd(_ value: String?) -> String {
        guard let value, let decimal = Decimal(string: value) else { return "—" }
        return usd(decimal)
    }

    static func usd(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD"))
    }

    /// An amount as a person says it: whole dollars without cents ("$160"), otherwise to the cent
    /// ("$39.50").
    static func dollars(_ value: String?) -> String {
        guard let value, var decimal = Decimal(string: value) else { return "—" }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 0, .plain)
        let whole = decimal == rounded
        return decimal.formatted(.currency(code: "USD").precision(.fractionLength(whole ? 0 : 2)))
    }

    /// Whether a symbol is a coin's dollar pair ("BTC/USD") rather than a stock: the engine writes
    /// every coin that way, and no stock has a slash.
    static func isCoin(_ symbol: String) -> Bool {
        symbol.contains("/")
    }

    /// The coin a pair trades: "BTC" of "BTC/USD".
    static func coin(_ symbol: String) -> String {
        String(symbol.split(separator: "/").first ?? Substring(symbol))
    }

    /// How much of a stock or coin, as a person reads it. A stock's shares are whole when within a
    /// hundredth of one ("1 share", "≈1 share"), otherwise to three decimals at most ("2.985
    /// shares"); "≈" marks a rounded count. A coin is counted to the billionth Alpaca keeps it in,
    /// with its code ("0.001231481 BTC"). `marksRounding: false` leaves the "≈" to a sentence that
    /// already says the count is an estimate.
    @MainActor
    static func shares(_ value: Decimal, of symbol: String, marksRounding: Bool = true) -> String {
        if isCoin(symbol) { return L10n.string("%@ units of %@", coinCount(value), coin(symbol)) }
        return L10n.string(isOne(value) ? "%@ share" : "%@ shares", shareCount(value, of: symbol, marksRounding: marksRounding))
    }

    /// What comes before "of" and the symbol in a sentence ("Bought %@ of %@"): a stock's shares
    /// ("2.985 shares" of PM), or a coin's count alone ("0.001231481" of BTC/USD), which the pair
    /// already names.
    @MainActor
    static func sharesOf(_ value: Decimal, symbol: String) -> String {
        isCoin(symbol) ? coinCount(value) : shares(value, of: symbol)
    }

    /// The count alone, rounded as `shares` rounds it: "≈1", "2.985", "0", or a coin's
    /// "0.001231481".
    @MainActor
    static func shareCount(_ value: Decimal, of symbol: String, marksRounding: Bool = true) -> String {
        if isCoin(symbol) { return coinCount(value) }
        var source = value
        var whole = Decimal()
        NSDecimalRound(&whole, &source, 0, .plain)
        var shown = whole
        if abs(NSDecimalNumber(decimal: value - whole).doubleValue) >= 0.01 {
            NSDecimalRound(&shown, &source, 3, .plain)
        }
        let text = shown.formatted(.number.precision(.fractionLength(0...3)))
        return shown == value || !marksRounding ? text : L10n.string("≈%@", text)
    }

    /// "0 of ≈1 share", "5 of 12 shares", "0.0005 of 0.001231481 BTC": part of an amount, as filled
    /// of an order.
    @MainActor
    static func shares(_ part: Decimal, of quantity: Decimal, symbol: String) -> String {
        if isCoin(symbol) {
            return L10n.string("%@ of %@ units of %@", coinCount(part), coinCount(quantity), coin(symbol))
        }
        return L10n.string(
            isOne(quantity) ? "%@ of %@ share" : "%@ of %@ shares", shareCount(part, of: symbol), shareCount(quantity, of: symbol))
    }

    /// A coin's count to the billionth, as Alpaca keeps it, with no trailing zeros: "0.001231481".
    @MainActor
    private static func coinCount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...9)).locale(AppTime.locale))
    }

    /// An amount of a stock, dollar first: "$200 of PM".
    @MainActor
    static func amount(_ dollars: String, of symbol: String) -> String {
        L10n.string("%@ of %@ stock", dollars, symbol)
    }

    private static func isOne(_ value: Decimal) -> Bool {
        abs(NSDecimalNumber(decimal: value).doubleValue - 1) < 0.01
    }

    /// A size on disk in the app's language: "0 KB", never "Zero kB".
    @MainActor
    static func bytes(_ value: Int64, style: ByteCountFormatStyle.Style = .file) -> String {
        value.formatted(.byteCount(style: style, spellsOutZero: false).locale(AppTime.locale))
    }

    /// Long revision hashes are only useful as short, recognizable prefixes.
    static func revision(_ value: String?, length: Int = 10) -> String {
        guard let value else { return "—" }
        return String(value.prefix(length))
    }
}
