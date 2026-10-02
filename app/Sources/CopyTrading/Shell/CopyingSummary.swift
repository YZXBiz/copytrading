import DesktopCore

/// What the sidebar footer says about copying, from the engine's trading status.
enum CopyingSummary {
    @MainActor
    static func of(_ status: TradingStatus?) -> (text: String, tone: StatusTone) {
        switch status?.state {
        case .running:
            (L10n.string("Copying"), .positive)
        case .degraded:
            // The engine reports "degraded" whenever something is not up yet (Discord connecting,
            // the model warming, an account opening), and adds an error code only when something
            // failed. No code means the start is still finishing; a code means a real problem.
            status?.errorCode == nil ? (L10n.string("Starting…"), .neutral) : (L10n.string("Copying with problems"), .caution)
        case .starting:
            (L10n.string("Starting…"), .neutral)
        case .pausing:
            (L10n.string("Pausing…"), .neutral)
        case .failed:
            (L10n.string("Copying stopped"), .critical)
        case .paused, nil:
            (L10n.string("Copying paused"), .inactive)
        }
    }
}
