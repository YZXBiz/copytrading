import DesktopCore
import SwiftUI

/// A restore that started but has not finished: resume it, or roll back.
struct PendingRestoreRows: View {
    let model: AppModel
    let pending: PendingRestoreCandidateView

    var body: some View {
        SettingsValueRow(
            label: "Restore candidate",
            value: L10n.string(pending.candidateValid ? "Passed validation" : "Failed validation"),
            detail: pending.candidateValid
                ? "Resume with a read-only broker check, or roll back to the previous generation."
                : "Roll back to the previous generation.",
            tone: pending.candidateValid ? .caution : .critical
        )
        .help(
            L10n.string(
                "Candidate %@\nPrevious generation %@\nActive generation %@",
                pending.candidateID,
                pending.previousGeneration,
                pending.activeGeneration
            ))
        SettingsActionRow(title: L10n.string("Resume Restore"), action: resume)
            .disabled(!model.canActivateOperationalRestore)
        SettingsActionRow(title: L10n.string("Roll Back Restore"), role: .destructive, action: rollback)
            .disabled(!model.canRollbackOperationalRestore)
    }

    private func resume() {
        Task { await model.activateOperationalRestore() }
    }

    private func rollback() {
        Task { await model.rollbackOperationalRestore() }
    }
}
