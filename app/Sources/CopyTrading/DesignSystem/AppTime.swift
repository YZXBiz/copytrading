import Foundation

/// Every time the app shows goes through here: in the time zone chosen in Settings (the Mac's own
/// by default) and the app's language.
@MainActor
enum AppTime {
    static var zone: TimeZone { AppTimeZonePreference.shared.zone }
    static var locale: Locale { AppLanguagePreference.shared.language.locale }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// A format in the app's zone and language.
    static func style(_ base: Date.FormatStyle, zone: TimeZone? = nil, locale: Locale? = nil) -> Date.FormatStyle {
        var style = base.locale(locale ?? Self.locale)
        style.timeZone = zone ?? Self.zone
        return style
    }

    /// A zone's short name beside a time, "PT" or "ET", falling back to "GMT-7".
    static func shortName(_ zone: TimeZone? = nil, locale: Locale? = nil) -> String {
        let zone = zone ?? Self.zone
        return zone.localizedName(for: .shortGeneric, locale: locale ?? Self.locale)
            ?? zone.abbreviation() ?? zone.identifier
    }

    /// A zone's full name for Settings, "Pacific Time".
    static func name(_ zone: TimeZone? = nil, locale: Locale? = nil) -> String {
        let zone = zone ?? Self.zone
        return zone.localizedName(for: .generic, locale: locale ?? Self.locale) ?? zone.identifier
    }
}
