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
        date.formatted(
            .dateTime.month(.abbreviated).day().hour().minute().locale(AppLanguagePreference.shared.language.locale)
        )
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

    static func age(since iso: String?, now: Date = .now) -> String? {
        guard let date = date(iso) else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
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

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    /// Long revision hashes are only useful as short, recognizable prefixes.
    static func revision(_ value: String?, length: Int = 10) -> String {
        guard let value else { return "—" }
        return String(value.prefix(length))
    }
}
