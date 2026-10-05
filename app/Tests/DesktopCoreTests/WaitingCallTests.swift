import DesktopCore
import Foundation
import Testing

/// A post as the engine reports it: one account's outcome, and the calls it read or suggests.
private func post(
    decision: String, status: String, outcomes: [String], instructions: [String] = [],
    suggested: [String] = [], at sourceAt: String = "2026-10-05T14:30:00Z"
) throws -> SourceActivity {
    let json = """
        {"sequence": 1, "source_id": "discord:1:2", "source_revision": 1,
         "source_at": "\(sourceAt)", "captured_at": "\(sourceAt)", "text": "sco 20",
         "capture_status": "delivered", "parse_status": "complete", "delivery_status": "delivered",
         "decision": "\(decision)", "parser_reason": "conditional", "parser_profile": "stock-reading-v3",
         "interpreted_by": "deepseek-flash", "instructions": [\(instructions.joined(separator: ","))],
         "suggested": [\(suggested.joined(separator: ","))],
         "source_event": {"event_type": "discord_message", "content": "sco 20", "embeds": [],
           "attachments": [], "attachments_omitted": 0, "capture_status": "complete", "payload_bytes": 6},
         "destinations": [{"account_id": "paper", "environment": "paper", "status": "\(status)",
           "instruction_outcomes": [\(outcomes.map { "\"\($0)\"" }.joined(separator: ","))], "orders": []}]}
        """
    return try JSONDecoder().decode(SourceActivity.self, from: Data(json.utf8))
}

private func buy(_ symbol: String, _ price: String) -> String {
    """
    {"action": "buy", "symbol": "\(symbol)", "price": "\(price)", "entry_price": null,
     "fraction": null, "exit_basis": null, "whole_position": false}
    """
}

@Test func aPostTheReaderLeftForTheOwnerWaitsWithItsSuggestedCalls() throws {
    let waiting = try #require(
        WaitingCall(try post(decision: "review", status: "review_required", outcomes: [], suggested: [buy("SCO", "20")])))

    #expect(waiting.accountIDs == ["paper"])
    #expect(waiting.calls.map(\.symbol) == ["SCO"])
}

@Test func aBuyHeldBecauseTheMarketMovedWaitsWithOnlyThatCall() throws {
    let traded = try post(
        decision: "trade", status: "done", outcomes: ["order_linked", "price_moved"],
        instructions: [buy("ABC", "25"), buy("DEF", "40")])

    let waiting = try #require(WaitingCall(traded))

    #expect(waiting.calls.map(\.symbol) == ["DEF"])
}

@Test(arguments: ["order_linked", "insufficient_cash"])
func aCallTheAccountTradedOrRefusedDoesNotWait(outcome: String) throws {
    let finished = try post(decision: "trade", status: "done", outcomes: [outcome], instructions: [buy("ABC", "25")])

    #expect(WaitingCall(finished) == nil)
}

@Test(arguments: [
    ("2026-10-05T19:59:00Z", false),  // 15:59 in New York, the same trading day
    ("2026-10-06T00:01:00Z", true),  // 20:01 in New York counts as the next trading day
    ("2026-10-06T14:00:00Z", true),  // the next morning
])
func aWaitingCallExpiresWhenItsTradingDayEnds(now: String, expired: Bool) throws {
    let waiting = try #require(
        WaitingCall(try post(decision: "review", status: "review_required", outcomes: [], suggested: [buy("SCO", "20")])))

    #expect(waiting.hasExpired(at: try Date(now, strategy: .iso8601)) == expired)
}
