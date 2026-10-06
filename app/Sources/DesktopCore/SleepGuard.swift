import Foundation

/// Keeps the Mac from idle-sleeping while CopyTrading copies, like Codex's "Prevent sleep while
/// running": the display may still sleep and the screen lock, but the system stays awake, so posts
/// are read and orders placed as they come. A closed MacBook lid still sleeps the Mac unless it is
/// plugged in with a display connected; nothing an app may do overrides that.
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
        begin: @escaping Begin = { ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: $0) },
        end: @escaping End = { ProcessInfo.processInfo.endActivity($0) }
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
