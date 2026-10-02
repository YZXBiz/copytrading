/// A window's automatic startup does not override a user's explicit Stop.
public struct AppStartupIntent: Sendable {
    public private(set) var allowsAutomaticStart = true

    public init() {}

    public mutating func stop() {
        allowsAutomaticStart = false
    }

    public mutating func startRequested() {
        allowsAutomaticStart = true
    }
}
