import DesktopCore
import Foundation
import Testing

/// The Activity card's words (ADR-0007): how it reads a post, which words it marks, and how a
/// post ended for each account.
@MainActor
func runActivityCardTests() throws {
    try readAsSaysEachCallInPlainWords()
    try aRepeatedNumberIsMarkedBesideTheOtherCitedWords()
    try aTrimmedBuyIsTradedSmallerAndSaysByHowMuch()
    try aSkipNamesTheLimitWithItsNumbers()
}

private func readings() throws -> [PostReading] {
    let contracts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Resources/Contracts")
    return try JSONDecoder().decode(
        [PostReading].self, from: Data(contentsOf: contracts.appending(path: "post-readings.json")))
}

@MainActor
private func readAsSaysEachCallInPlainWords() throws {
    let lines = try readings().map { ReadAsText.lines($0).joined(separator: " | ") }

    try #require(
        lines == [
            "Sell half of the IREN bought at $39.50, at $41.27.",
            "Buy SOUN at $5.85, a sixth of a full position.",
            "Sell all of RCL, at $260.",
            "Buy CBRS between $160 and $179.",
            "Buy SCO at $20, batch 1.",
            "Buy SCO at the market price.",
            "TSLA 373 is still resistance today",
            "The reader couldn't tell what this post means.",
        ], "Read as lines changed: \(lines)")
    try #require(
        try ReadAsText.facts(readings()[3].calls[0]) == ["Buy", "CBRS", "$160–$179", "no size"],
        "Read as facts changed")
}

@MainActor
private func aRepeatedNumberIsMarkedBesideTheOtherCitedWords() throws {
    let post = "Cbrs 上次叫大家217 盈利跑路，现在179 又是机会。建仓区域160-179， 跑路区域210 以上"

    let ranges = CitedWordMarks.ranges(of: ["建仓", "Cbrs", "160", "179"], in: post)
    let marks = ranges.map { String(post[$0]) }
    let range179 = try #require(ranges.last)

    try #require(marks == ["建仓", "Cbrs", "160", "179"], "marked \(marks)")
    try #require(post[range179.lowerBound...].hasPrefix("179，"), "the range's 179 was not the one marked")
}

private func activity(destination: String, decision: String = "trade", instructions: String) throws -> SourceActivity {
    let json = """
        {"sequence": 1, "source_id": "discord:1:2", "source_revision": 1, "source_at": "2026-10-05T14:30:00Z",
         "captured_at": "2026-10-05T14:30:00Z", "text": "post", "capture_status": "delivered",
         "parse_status": "complete", "delivery_status": "delivered", "decision": "\(decision)",
         "parser_reason": "Bought", "parser_profile": "stock-reading-v3", "interpreted_by": "deepseek-flash",
         "instructions": [\(instructions)], "suggested": [], "reading": null,
         "source_event": {"event_type": "discord_message", "content": "post", "embeds": [], "attachments": [],
           "attachments_omitted": 0, "capture_status": "complete", "payload_bytes": 4},
         "destinations": [\(destination)]}
        """
    return try JSONDecoder().decode(SourceActivity.self, from: Data(json.utf8))
}

private let soun = """
    {"action": "buy", "symbol": "SOUN", "price": "5.85", "entry_price": null, "fraction": "0.1667",
     "exit_basis": null, "whole_position": false}
    """

@MainActor
private func aTrimmedBuyIsTradedSmallerAndSaysByHowMuch() throws {
    let source = try activity(
        destination: """
            {"account_id": "zhao-paper", "environment": "paper", "status": "done",
             "instruction_outcomes": ["order_linked"], "limits_hit": [],
             "orders": [{"client_id": "c1", "symbol": "SOUN", "side": "buy", "status": "filled", "quantity": "42",
               "filled_quantity": "42", "limit_price": "5.85", "average_fill_price": "5.85", "broker_id": "b1",
               "created_at": "2026-10-05T14:30:01Z", "instruction_index": 0, "requested_usd": "333.33",
               "budget_usd": "250"}]}
            """, instructions: soun)

    let outcome = ActivityCardOutcome(source, skipped: false)

    try #require(outcome.title == "Traded smaller", "badge was \(outcome.title)")
    let line = try #require(outcome.accounts.first?.lines.first)
    try #require(line.what == "Bought 42 SOUN at $5.85", "what was \(line.what)")
    try #require(
        line.why == "The call was for $333.33. Your max per order cut it to $250.",
        "why was \(line.why ?? "nil")")
}

@MainActor
private func aSkipNamesTheLimitWithItsNumbers() throws {
    let source = try activity(
        destination: """
            {"account_id": "zhao-paper", "environment": "paper", "status": "done",
             "instruction_outcomes": ["symbol_exposure_cap"],
             "limits_hit": [{"part": 0, "scope": "symbol", "current": "1900", "proposed": "333.33", "limit": "2000"}],
             "orders": []}
            """, instructions: soun)

    let outcome = ActivityCardOutcome(source, skipped: false)

    try #require(outcome.title == "Skipped", "badge was \(outcome.title)")
    try #require(
        outcome.accounts.first?.lines
            == [
                .init(
                    what: "Not bought",
                    why:
                        "zhao-paper already has $1,900 of SOUN. Buying $333.33 more would go over its $2,000 limit for one stock."
                )
            ], "lines were \(outcome.accounts.first?.lines ?? [])")
}
