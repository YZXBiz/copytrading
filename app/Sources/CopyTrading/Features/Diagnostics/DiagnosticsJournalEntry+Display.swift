import Foundation
import DesktopCore

extension DiagnosticsJournalEntry {
    /// What happened, in words.
    @MainActor
    var title: String {
        switch kind {
        case .stage:
            L10n.string(Self.stageTitles[name] ?? "Self-test step")
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
            case "execution.ledger_event": L10n.string(Self.ledgerTitles[outcome] ?? "Ledger entry")
            default: L10n.string("Trading step")
            }
        }
    }

    /// A self-test's stages, as the Engine page's self-test line names them.
    static let stageTitles: [String: String] = [
        "captured": "Self-test captured",
        "parsed": "Self-test read",
        "completed": "Self-test finished",
        "failed": "Self-test failed",
    ]

    /// Every ledger event the engine journals (`safe_ledger_event`), short enough for the list.
    static let ledgerTitles: [String: String] = [
        "account_bound": "Account connected",
        "signal_rejected": "Post refused",
        "message": "Post received",
        "skipped": "Order skipped",
        "message_done": "Post finished",
        "order_prepared": "Order prepared",
        "submit_started": "Order sending",
        "submission_aborted": "Order not sent",
        "submission_uncertain": "Order unconfirmed",
        "broker_acknowledged": "Broker accepted",
        "cancel_requested": "Cancel asked",
        "quote_unavailable": "No quote",
        "submit_error": "Order refused",
        "submission_quote": "Quote at sending",
        "manual_sale_recorded": "Sale recorded",
        "order_intent_released": "Order released",
        "late_order_incident_cleared": "Late order cleared",
        "order_update": "Order update",
        "late_order_incident_opened": "Late order found",
        "late_order_incident_reopened": "Late order found again",
    ]

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
        case "accepted": L10n.string("Accepted")
        case "parsed": L10n.string("Read")
        case "completed": L10n.string("Completed")
        case "failed", "error": L10n.string("Failed")
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
            "symbol", "qty", "limit_price", "source_price", "status", "filled_qty", "filled_avg_price", "reason",
            "previous_stage", "provider", "command_id", "workflow_id", "trace_id",
            "destination_id", "attempt", "signal_ref", "payload_bytes", "redacted_fields",
        ]
        let byName = Dictionary(fields.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        // A coin's quantities read to the billionth; a stock's, as shares.
        let symbol = byName["symbol"] ?? ""
        return shown.compactMap { name in
            guard let value = byName[name] else { return nil }
            switch name {
            // What a ledger event was about: the order and its outcome, or why it was skipped.
            case "symbol":
                let side = byName["side"].map { L10n.string($0 == "sell" ? "Sell" : "Buy") }
                return (L10n.string("Stock"), [side, value].compactMap { $0 }.joined(separator: " "))
            case "qty": return (L10n.string("Shares"), Decimal(engine: value).map { Humanize.shareCount($0, of: symbol) } ?? value)
            case "limit_price": return (L10n.string("Limit price"), Decimal(engine: value).map(Humanize.usd) ?? value)
            case "source_price": return (L10n.string("Guru's price"), Decimal(engine: value).map(Humanize.usd) ?? value)
            case "status": return (L10n.string("Status"), L10n.string(Humanize.code(value)))
            case "filled_qty": return (L10n.string("Filled"), Decimal(engine: value).map { Humanize.shareCount($0, of: symbol) } ?? value)
            case "filled_avg_price": return (L10n.string("Average fill"), Decimal(engine: value).map(Humanize.usd) ?? value)
            case "reason": return (L10n.string("Reason"), Reason.text(value))
            case "previous_stage": return (L10n.string("After"), L10n.string(Self.stageTitles[value] ?? Humanize.code(value)))
            // A post from Discord has no model provider; the engine journals "other".
            case "provider":
                guard let provider = TradingProviderName(rawValue: value) else { return nil }
                return (L10n.string("Provider"), provider.title)
            case "command_id": return (L10n.string("Command"), value)
            case "workflow_id": return (L10n.string("Workflow"), value)
            case "trace_id": return (L10n.string("Trace"), value)
            case "destination_id": return (L10n.string("Destination"), value)
            case "attempt": return (L10n.string("Attempt"), value)
            case "signal_ref": return (L10n.string("Signal"), value)
            case "payload_bytes": return (L10n.string("Payload size"), Int64(value).map { Humanize.bytes($0) } ?? value)
            case "redacted_fields": return (L10n.string("Values redacted"), value)
            default: return nil
            }
        }
    }
}
