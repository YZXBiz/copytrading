import DesktopCore

extension StatusTone {
    init(_ state: AppModel.RuntimeState) {
        switch state {
        case .ready: self = .positive
        case .starting: self = .neutral
        case .degraded: self = .caution
        case .failed: self = .critical
        case .stopped: self = .inactive
        }
    }

    init(_ state: TradingRunState?) {
        switch state {
        case .running: self = .positive
        case .starting, .pausing: self = .neutral
        case .degraded: self = .caution
        case .failed: self = .critical
        case .paused, nil: self = .inactive
        }
    }

    init(_ state: TradingCapabilityState) {
        switch state {
        case .ready: self = .positive
        case .failed: self = .critical
        case .notConfigured: self = .inactive
        }
    }

    /// Engine status strings are open-ended; classify them by their whole words, so "broker"
    /// never reads as "ok" and "disconnected" never reads as "connected".
    init(code: String?) {
        let words = Set(
            (code ?? "").lowercased().split { !$0.isLetter }.map(String.init)
        )
        guard !words.isEmpty else {
            self = .inactive
            return
        }
        if !words.isDisjoint(with: Self.criticalWords) {
            self = .critical
        } else if !words.isDisjoint(with: Self.cautionWords) {
            self = .caution
        } else if !words.isDisjoint(with: ["not", "no", "none", "inactive", "ignored", "ignore"]) {
            self = .inactive
        } else if !words.isDisjoint(with: Self.positiveWords) {
            self = .positive
        } else {
            self = .neutral
        }
    }

    private static let criticalWords: Set<String> = [
        "fail", "failed", "failure", "error", "reject", "rejected", "blocked", "unavailable",
        "denied", "invalid", "mismatch", "disconnected", "conflict",
    ]

    private static let cautionWords: Set<String> = [
        "review", "pending", "degraded", "paused", "disabled", "stale", "partial", "timeout", "unknown",
        "limited", "uncertain", "retrying", "expired",
    ]

    private static let positiveWords: Set<String> = [
        "ready", "filled", "delivered", "enabled", "current", "within", "running", "recorded",
        "trade", "healthy", "submitted", "accepted", "queryable", "complete", "completed",
        "success", "succeeded", "passed", "connected", "matches", "parsed", "ok",
    ]
}
