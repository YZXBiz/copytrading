import CopyTradingTestSupport
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
    try aCallHeldForApprovalAsksToBeApproved()
    try aBuyHeldForAResumeAsksToResumeByItsDeadline()
    try aDeadlineReadsOnTheOwnersClock()
}

private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let english = Locale(identifier: "en_US")

/// Times format with a narrow no-break space before AM/PM; compare them as people read them.
private func plain(_ text: String?) -> String? {
    text?.replacingOccurrences(of: "\u{202F}", with: " ")
}

/// A waiting call's deadline, 20:00 New York, in the owner's zone, said as today, tomorrow, or a day.
@MainActor
private func aDeadlineReadsOnTheOwnersClock() throws {
    let deadline = WaitingCall.endOfTradingDay(of: try Date("2026-10-05T15:00:00Z", strategy: .iso8601))
    let morning = try Date("2026-10-05T15:00:00Z", strategy: .iso8601)
    let dayBefore = try Date("2026-10-04T20:00:00Z", strategy: .iso8601)
    let daysBefore = try Date("2026-10-02T15:00:00Z", strategy: .iso8601)
    let today = plain(TradingDeadlineText.text(deadline, now: morning, zone: losAngeles, locale: english))
    try #require(today == "5:00 PM today", "the deadline read \(today ?? "nil")")
    let tomorrow = plain(TradingDeadlineText.text(deadline, now: dayBefore, zone: losAngeles, locale: english))
    try #require(tomorrow == "5:00 PM tomorrow", "the deadline read \(tomorrow ?? "nil")")
    let later = plain(TradingDeadlineText.text(deadline, now: daysBefore, zone: losAngeles, locale: english))
    try #require(later == "Mon 5:00 PM", "the deadline read \(later ?? "nil")")
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
            "Buy SOUN at $5.85, a sixth of a full position. A re-post of an earlier call.",
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

/// A SOUN buy of a sixth, as zhao-paper saw it.
private func soun() -> SourceActivityBuilder {
    SourceActivityBuilder().decision("trade", reason: "Bought").calls([SourceActivityBuilder.buy("SOUN", "5.85", fraction: "0.1667")])
}

@MainActor
private func aTrimmedBuyIsTradedSmallerAndSaysByHowMuch() throws {
    let source = try soun()
        .destination(
            "zhao-paper", status: "done", outcomes: ["order_linked"],
            orders: [
                [
                    "client_id": "c1", "symbol": "SOUN", "side": "buy", "status": "filled", "quantity": "42",
                    "filled_quantity": "42", "limit_price": "5.85", "average_fill_price": "5.85", "broker_id": "b1",
                    "created_at": "2026-10-05T14:30:01Z", "instruction_index": 0, "requested_usd": "333.33",
                    "budget_usd": "250",
                ]
            ]
        )
        .build()

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
    let source = try soun()
        .destination(
            "zhao-paper", status: "done", outcomes: ["symbol_exposure_cap"],
            limits: [["part": 0, "scope": "symbol", "current": "1900", "proposed": "333.33", "limit": "2000"]]
        )
        .build()

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

@MainActor
private func aCallHeldForApprovalAsksToBeApproved() throws {
    let source = try soun().destination("zhao-paper", status: "done", outcomes: ["approval_required"]).build()
    let sameDay = try Date("2026-10-05T15:00:00Z", strategy: .iso8601)
    let nextDay = try Date("2026-10-06T15:00:00Z", strategy: .iso8601)

    let open = ActivityCardOutcome(source, skipped: false, now: sameDay, zone: losAngeles, locale: english)
    let late = ActivityCardOutcome(source, skipped: false, now: nextDay)

    try #require(open.title == "Waiting for you", "badge was \(open.title)")
    try #require(open.accounts.first?.lines.first?.what == "Waiting for your approval", "lines were \(open.accounts.first?.lines ?? [])")
    try #require(
        plain(open.accounts.first?.lines.first?.why)
            == "You asked to approve every order for this account. Approve it by 5:00 PM today, when trading ends.",
        "lines were \(open.accounts.first?.lines ?? [])")
    try #require(open.accounts.first?.waits == true, "the account did not wait")
    try #require(
        late.accounts.first?.lines.first?.what == "Not sent",
        "an expired approval read \(late.accounts.first?.lines.first?.what ?? "nil")")
}

@MainActor
private func aBuyHeldForAResumeAsksToResumeByItsDeadline() throws {
    // Posted 14:30:00Z; entries wait for the owner's Resume after a restart.
    let source = try soun().destination("zhao-paper", status: "pending", outcomes: ["pending"]).build()
    let resume = ResumeWait(source, waiting: ["zhao-paper"], signalAge: { _ in 120 })
    let posted = try Date("2026-10-05T14:30:00Z", strategy: .iso8601)

    try #require(
        resume.deadlines["zhao-paper"] == posted.addingTimeInterval(120),
        "deadline was \(String(describing: resume.deadlines["zhao-paper"]))")
    let waiting = ActivityCardOutcome(source, skipped: false, resume: resume, now: posted.addingTimeInterval(30))
    try #require(waiting.title == "Waiting for you", "badge was \(waiting.title)")
    let account = try #require(waiting.accounts.first)
    try #require(account.awaitsResume, "the account did not ask for a resume")
    let line = try #require(account.lines.first)
    try #require(line.what == "Waiting for you to resume entries in zhao-paper", "what was \(line.what)")
    try #require(line.why?.hasPrefix("Resume by ") == true, "why was \(line.why ?? "nil")")
    let late = ActivityCardOutcome(source, skipped: false, resume: resume, now: posted.addingTimeInterval(300))
    try #require(
        late.accounts.first?.lines.first?.why?.hasPrefix("Resume now") == true,
        "a late resume read \(late.accounts.first?.lines.first?.why ?? "nil")")

    // Without a waiting account, or once an order went out, nothing asks for a resume.
    let ready = ActivityCardOutcome(
        source, skipped: false, resume: ResumeWait(source, waiting: [], signalAge: { _ in 120 }))
    try #require(ready.accounts.first?.awaitsResume == false, "a ready account asked for a resume")
    try #require(
        ready.accounts.first?.lines.first?.what == "Waiting to be sized and sent",
        "a ready account read \(ready.accounts.first?.lines.first?.what ?? "nil")")
    let skippedBuy = try soun().destination("zhao-paper", status: "done", outcomes: ["stale_waiting_for_resume"]).build()
    try #require(
        ResumeWait(skippedBuy, waiting: ["zhao-paper"], signalAge: { _ in 120 }).deadlines.isEmpty,
        "a buy already skipped as too old still asked for a resume")
}
