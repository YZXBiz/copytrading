import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// A post as the engine reports it: one account's outcome, and the calls it read or suggests.
private func post(
    decision: String, status: String, outcomes: [String], instructions: [[String: Any]] = [],
    suggested: [[String: Any]] = [], at sourceAt: String = "2026-10-05T14:30:00Z"
) throws -> SourceActivity {
    try SourceActivityBuilder()
        .text("sco 20").posted(at: sourceAt).decision(decision, reason: "conditional")
        .calls(instructions).suggested(suggested)
        .destination("paper", status: status, outcomes: outcomes)
        .build()
}

private func buy(_ symbol: String, _ price: String) -> [String: Any] {
    SourceActivityBuilder.buy(symbol, price)
}

@Test func aPostTheReaderLeftForTheOwnerWaitsWithItsSuggestedCalls() throws {
    let waiting = try #require(
        WaitingCall(try post(decision: "review", status: "review_required", outcomes: [], suggested: [buy("SCO", "20")])))

    #expect(waiting.accountIDs == ["paper"])
    #expect(waiting.calls.map(\.symbol) == ["SCO"])
}

@Test func aBuyHeldForApprovalWaitsWithOnlyThatCall() throws {
    let traded = try post(
        decision: "trade", status: "done", outcomes: ["order_linked", "approval_required"],
        instructions: [buy("ABC", "25"), buy("DEF", "40")])

    let waiting = try #require(WaitingCall(traded))

    #expect(waiting.calls.map(\.symbol) == ["DEF"])
}

@Test func aBuyHeldForApprovalWaitsToBeApprovedNotCopied() throws {
    let held = try post(decision: "trade", status: "done", outcomes: ["approval_required"], instructions: [buy("ABC", "25")])

    let waiting = try #require(WaitingCall(held))

    #expect(waiting.calls.map(\.symbol) == ["ABC"])
    #expect(waiting.awaitsApproval)
}

@Test func aPostLeftForReviewIsCopiedNotApproved() throws {
    let review = try post(decision: "review", status: "review_required", outcomes: [], suggested: [buy("SCO", "20")])

    #expect(try #require(WaitingCall(review)).awaitsApproval == false)
}

@Test func aSkipThatIsNoLongerAHoldDoesNotWait() throws {
    // `price_moved` was a hold until the market-move check was removed; old history must not wait.
    let old = try post(decision: "trade", status: "done", outcomes: ["price_moved"], instructions: [buy("ABC", "25")])

    #expect(WaitingCall(old) == nil)
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
