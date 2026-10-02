import DesktopCore

extension TelemetryState {
    @MainActor
    var title: String {
        switch self {
        case .healthy: L10n.string("Recording")
        case .degraded: L10n.string("Degraded")
        }
    }

    var tone: StatusTone {
        switch self {
        case .healthy: .positive
        case .degraded: .caution
        }
    }
}
