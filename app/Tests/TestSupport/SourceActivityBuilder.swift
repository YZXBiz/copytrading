import DesktopCore
import Foundation

/// A post as the engine reports it in Activity, built with sensible defaults so a test states only
/// the calls, decision and outcomes it is about (a Test Data Builder: *AI Driven Swift
/// Architecture*, ch. 4). Calls and destinations take the engine's own wire fields.
public struct SourceActivityBuilder {
    private var payload: [String: Any] = [
        "sequence": 1, "source_id": "discord:1:2", "source_revision": 1,
        "source_at": "2026-10-05T14:30:00Z", "captured_at": "2026-10-05T14:30:00Z", "text": "post",
        "capture_status": "delivered", "parse_status": "complete", "delivery_status": "delivered",
        "decision": "trade", "parser_reason": "x", "parser_profile": "stock-reading-v3",
        "interpreted_by": "deepseek-flash", "instructions": [Any](), "suggested": [Any](),
        "destinations": [Any](),
    ]

    public init() {}

    public func text(_ text: String) -> Self { setting("text", text) }
    public func posted(at iso: String) -> Self { setting("source_at", iso).setting("captured_at", iso) }
    public func sequence(_ sequence: Int, sourceID: String) -> Self {
        setting("sequence", sequence).setting("source_id", sourceID)
    }
    public func decision(_ decision: String?, reason: String? = nil) -> Self {
        setting("decision", decision ?? NSNull()).setting("parser_reason", reason ?? NSNull())
    }
    /// The calls the reader made; `suggested` for a post left for the owner.
    public func calls(_ calls: [[String: Any]]) -> Self { setting("instructions", calls) }
    public func suggested(_ calls: [[String: Any]]) -> Self { setting("suggested", calls) }
    public func reading(_ reading: PostReading) throws -> Self {
        setting("reading", try JSONSerialization.jsonObject(with: JSONEncoder().encode(reading)))
    }
    public func destination(
        _ account: String, status: String, outcomes: [String] = [], environment: String = "paper",
        limits: [[String: Any]] = [], orders: [[String: Any]] = []
    ) -> Self {
        var copy = self
        var destinations = copy.payload["destinations"] as? [Any] ?? []
        destinations.append([
            "account_id": account, "environment": environment, "status": status,
            "instruction_outcomes": outcomes, "limits_hit": limits, "orders": orders,
        ])
        copy.payload["destinations"] = destinations
        return copy
    }

    public func build() throws -> SourceActivity {
        var payload = payload
        let text = payload["text"] as? String ?? ""
        payload["source_event"] = [
            "event_type": "discord_message", "content": text, "embeds": [Any](), "attachments": [Any](),
            "attachments_omitted": 0, "capture_status": "complete", "payload_bytes": text.utf8.count,
        ]
        return try JSONDecoder().decode(SourceActivity.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    /// A buy call in the engine's wire shape.
    public static func buy(_ symbol: String, _ price: String, fraction: String? = nil) -> [String: Any] {
        [
            "action": "buy", "symbol": symbol, "price": price, "entry_price": NSNull(),
            "fraction": fraction ?? NSNull(), "exit_basis": NSNull(),
        ]
    }

    private func setting(_ key: String, _ value: Any) -> Self {
        var copy = self
        copy.payload[key] = value
        return copy
    }
}
