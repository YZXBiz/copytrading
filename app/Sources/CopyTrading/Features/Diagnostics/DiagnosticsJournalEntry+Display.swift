import DesktopCore

extension DiagnosticsJournalEntry {
    /// What happened, in words.
    @MainActor
    var title: String {
        switch kind {
        case .stage:
            L10n.string("Self-test %@", L10n.string(Humanize.code(name).lowercased()))
        case .payload:
            switch name {
            case "source_event": L10n.string("Source post")
            case "model_request": L10n.string("Model request")
            case "model_response": L10n.string("Model reply")
            default: L10n.string("Captured payload")
            }
        case .trading:
            switch name {
            case "source.forward": L10n.string("Post forwarded")
            case "workflow": L10n.string("Workflow step")
            case "model.parse": L10n.string("Interpretation")
            case "destination.receive": L10n.string("Account delivery")
            case "execution.risk_checks": L10n.string("Risk checks")
            case "execution.order_submission": L10n.string("Order submission")
            case "execution.quote_snapshot": L10n.string("Quote snapshot")
            case "execution.ledger_event": L10n.string("Ledger: %@", L10n.string(Humanize.code(outcome).lowercased()))
            default: L10n.string("Trading step")
            }
        }
    }

    /// How it ended, in words; ledger events carry their name in the title instead.
    @MainActor
    var outcomeTitle: String {
        switch outcome {
        case "returned": L10n.string("Completed")
        case "raised": L10n.string("Failed")
        case "observed": L10n.string("Recorded")
        case "complete": L10n.string("Captured")
        case "oversize": L10n.string("Too large")
        case "missing": L10n.string("Missing")
        case "incomplete": L10n.string("Not captured")
        default: kind == .trading && name == "execution.ledger_event" ? L10n.string("Recorded") : L10n.string(Humanize.code(outcome))
        }
    }

    var tone: StatusTone {
        switch outcome {
        case "raised", "failed", "error", "oversize", "missing", "incomplete",
            "submit_error", "submission_aborted", "submission_uncertain", "quote_unavailable",
            "signal_rejected", "late_order_incident_opened", "late_order_incident_reopened":
            .caution
        default:
            .positive
        }
    }

    var symbol: String {
        switch kind {
        case .stage: "checklist"
        case .payload:
            switch name {
            case "source_event": "text.bubble"
            case "model_request": "arrow.up.message"
            case "model_response": "arrow.down.message"
            default: "doc.text"
            }
        case .trading: "arrow.triangle.branch"
        }
    }

    /// The fields worth reading: what the title and badge already say, and internal flags, are left out.
    @MainActor
    var displayFields: [(label: String, value: String)] {
        let shown: [String] = [
            "previous_stage", "provider", "command_id", "workflow_id", "trace_id",
            "destination_id", "attempt", "signal_ref", "payload_bytes", "redacted_fields",
        ]
        let byName = Dictionary(fields.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        return shown.compactMap { name in
            guard let value = byName[name] else { return nil }
            switch name {
            case "previous_stage": return (L10n.string("After"), Humanize.code(value))
            case "provider": return (L10n.string("Provider"), TradingProviderName(rawValue: value)?.title ?? Humanize.code(value))
            case "command_id": return (L10n.string("Command"), value)
            case "workflow_id": return (L10n.string("Workflow"), value)
            case "trace_id": return (L10n.string("Trace"), value)
            case "destination_id": return (L10n.string("Destination"), value)
            case "attempt": return (L10n.string("Attempt"), value)
            case "signal_ref": return (L10n.string("Signal"), value)
            case "payload_bytes": return (L10n.string("Payload size"), Int64(value).map(Humanize.bytes) ?? value)
            case "redacted_fields": return (L10n.string("Values redacted"), value)
            default: return nil
            }
        }
    }
}
