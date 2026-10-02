import Foundation

extension Decimal {
    /// Engine amounts arrive as exact decimal strings; nil when a value is missing or malformed.
    init?(engine value: String?) {
        guard let value, let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self = decimal
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
