import Foundation

/// The newer version the updater found, as the banner offers it. Later puts that version off
/// until the next launch; a newer one is offered again.
@MainActor
@Observable
public final class UpdateOffer {
    /// The version to offer now, or nil when there is none or the owner put it off.
    public private(set) var version: String?
    /// The folder the app sits in when macOS won't let the updater replace it there: the banner
    /// asks to move the app instead of offering Install.
    public private(set) var blockingFolder: String?
    private var postponed: Set<String> = []

    nonisolated public init() {}

    public func found(_ version: String, blockedIn folder: String? = nil) {
        self.version = postponed.contains(version) ? nil : version
        blockingFolder = self.version == nil ? nil : folder
    }

    /// Later: this version waits until the app launches again.
    public func postpone() {
        if let version { postponed.insert(version) }
        withdraw()
    }

    /// Sparkle took over (its window opened, or the session ended): the banner steps aside.
    public func withdraw() {
        version = nil
        blockingFolder = nil
    }
}
