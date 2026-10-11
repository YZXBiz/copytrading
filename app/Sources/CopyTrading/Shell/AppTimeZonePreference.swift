import Foundation
import Observation

/// The time zone every time in the app is shown in: the Mac's own by default, which follows the
/// Mac when it changes, or one the owner picked in Settings (New York's market time, say).
@MainActor
@Observable
final class AppTimeZonePreference {
    static let storageKey = "appTimeZone"
    static let shared = AppTimeZonePreference()
    static let newYork = "America/New_York"

    /// A zone identifier the owner chose; nil follows the Mac.
    private(set) var chosen: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.storageKey)
        chosen = stored.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 }
    }

    var zone: TimeZone {
        chosen.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    var isAutomatic: Bool { chosen == nil }

    /// Follow the Mac (nil) or use one zone from now on.
    func select(_ identifier: String?) {
        chosen = identifier.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 }
        if let chosen {
            defaults.set(chosen, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
