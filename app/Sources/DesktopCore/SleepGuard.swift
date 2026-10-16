import Foundation

/// Keeps the Mac awake while CopyTrading copies: the display may still sleep and the screen lock,
/// but the system stays awake, so posts are read and orders placed as they come. Plugged in, a
/// closed MacBook lid stays awake too; on battery, closing the lid still sleeps it.
@MainActor
public final class SleepGuard {
    public typealias Begin = @MainActor (String) -> any NSObjectProtocol
    public typealias End = @MainActor (any NSObjectProtocol) -> Void

    private let begin: Begin
    private let end: End
    private var activity: (any NSObjectProtocol)?

    /// The reason macOS shows for it, in Activity Monitor and `pmset -g assertions`.
    public static let reason = "CopyTrading is copying trades"

    public init(
        begin: @escaping Begin = { AwakeClaim(reason: $0) },
        end: @escaping End = { ($0 as? AwakeClaim)?.release() }
    ) {
        self.begin = begin
        self.end = end
    }

    public var isHolding: Bool { activity != nil }

    /// Holds the Mac awake or lets it sleep again; asking twice for the same thing does nothing.
    public func hold(_ awake: Bool) {
        if awake, activity == nil {
            activity = begin(Self.reason)
        } else if !awake, let held = activity {
            end(held)
            activity = nil
        }
    }
}
