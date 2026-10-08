import DesktopCore

/// Whether an account is taking new entries, in words and a tone, from the engine's own
/// readiness values (enabled, enabled_waiting_for_session, manual_resume_required, …).
@MainActor
struct AccountEntryState: Equatable {
    let text: String
    let tone: StatusTone

    init(_ account: AccountOverview) {
        guard account.activeConfiguration else {
            (text, tone) = ("Not in setup", .inactive)
            return
        }
        switch account.entryPermission {
        case "paused": (text, tone) = ("Entries paused", .inactive)
        case "disabled": (text, tone) = ("Entries off", .inactive)
        default:
            switch account.readiness {
            case "enabled": (text, tone) = ("Taking entries", .positive)
            case "enabled_waiting_for_session": (text, tone) = ("Taking entries at the open", .positive)
            case "manual_resume_required": (text, tone) = ("Waiting for you to resume", .caution)
            case "recovery_pending": (text, tone) = ("Checking the account", .neutral)
            case "inactive_evidence", "processing_stopped": (text, tone) = ("Not copying right now", .inactive)
            default: (text, tone) = (Reason.text(account.readiness), .caution)
            }
        }
    }
}
