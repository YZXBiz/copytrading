import Foundation

/// Whether copying was on the last time CopyTrading looked, so the next launch can say that it came
/// back with copying paused. Every status the engine reports updates it, so it needs no goodbye:
/// a quit, a crash, and a Mac restart all leave it as it was, and only a status that says copying
/// is paused (the owner pressed Stop Copying) clears it.
///
/// The app passes its preferences; without any, the memory lasts only as long as the object, which
/// is what tests and previews want.
public final class CopyingMemory {
    public static let key = "copying.wasOn"

    private let defaults: UserDefaults?
    private var remembered = false

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
    }

    public var wasOn: Bool { defaults?.bool(forKey: Self.key) ?? remembered }

    /// Notes what the engine reports. No status (the engine is down or restarting) and a failed
    /// start change nothing: the last thing known stays the last thing known.
    public func observe(_ state: TradingRunState?) {
        switch state {
        case .running, .degraded, .starting: set(true)
        case .paused, .pausing: set(false)
        case .failed, nil: break
        }
    }

    private func set(_ on: Bool) {
        guard on != wasOn else { return }
        if let defaults {
            if on { defaults.set(true, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        } else {
            remembered = on
        }
    }
}
