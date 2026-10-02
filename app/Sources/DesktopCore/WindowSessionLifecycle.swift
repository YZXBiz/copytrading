import Foundation

/// Tracks the owner-authentication token associated with the currently observed native window.
@MainActor
public final class WindowSessionLifecycle {
    private weak var activeWindow: AnyObject?
    private var activeSessionID: UUID?

    public init() {}

    /// Installs a token for a window opening and returns the replaced session, if any.
    @discardableResult
    public func attach(to window: AnyObject, sessionID: UUID) -> UUID? {
        guard activeWindow !== window || activeSessionID != sessionID else { return nil }
        let replacedSessionID = activeSessionID
        activeWindow = window
        activeSessionID = sessionID
        return replacedSessionID
    }

    /// A delayed close from an earlier opening of the same window cannot close its new session.
    public func close(_ window: AnyObject, sessionID: UUID) -> UUID? {
        guard activeWindow === window, activeSessionID == sessionID else { return nil }
        activeWindow = nil
        activeSessionID = nil
        return sessionID
    }
}
