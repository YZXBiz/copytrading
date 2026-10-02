import DesktopCore
import SwiftUI

/// One recorded agent request or owner decision.
struct AgentAuditRow: View {
    let entry: AgentAuditEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(Humanize.code(entry.operation)))
                Text("\(caller) · \(Humanize.relative(entry.at))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(outcome, tone: tone)
        }
    }

    private var caller: String {
        if entry.actor == "owner" { return L10n.string("You") }
        return AgentCallerName.describe(entry.callerPath)
    }

    private var outcome: String {
        switch entry.outcome {
        case "ok": L10n.string("Done")
        case "proposed": L10n.string("Waiting for you")
        default: L10n.string(Humanize.code(entry.outcome))
        }
    }

    private var tone: StatusTone {
        switch entry.outcome {
        case "ok", "approved", "succeeded": .positive
        case "proposed": .neutral
        case "locked", "forbidden", "busy", "cooling_down", "proposal_limit", "rejected", "expired": .caution
        case "failed", "outcome_unknown", "unavailable", "invalid_request", "conflict": .critical
        default: .inactive
        }
    }
}
