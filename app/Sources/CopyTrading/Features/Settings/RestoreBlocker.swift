import Foundation

/// Why a restore was refused, in words that say what to do about it.
enum RestoreBlocker {
    @MainActor static func reason(_ code: String) -> String {
        switch code {
        case "broker_state_mismatch":
            L10n.string("Alpaca's orders or holdings changed since the backup")
        case "broker_evidence_unavailable":
            L10n.string("Alpaca could not be reached to check the backup")
        case "account_identity_mismatch":
            L10n.string("the backup's account doesn't match the keys on this Mac")
        case "account_outbox_pending":
            L10n.string("a notification in the backup was never sent")
        case "application_work_pending":
            L10n.string("posts in the backup were still being read")
        case "account_snapshot_incomplete":
            L10n.string("an account in the backup is incomplete")
        case "candidate_changed", "candidate_invalid":
            L10n.string("the backup's files changed or failed their check")
        default:
            Humanize.code(code)
        }
    }
}
