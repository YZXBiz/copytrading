import DesktopCore

/// A connection's latest check, and a digest of exactly what was checked, so the result stops
/// counting the moment any of it is edited.
struct ConnectionCheckResult: Equatable {
    let fingerprint: Int
    /// Nil while the check is still running.
    let check: TradingCapabilityCheck?

    var isChecking: Bool { check == nil }
}
