import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// Activity's timeline and its cancel reasons, from the owner's real "buy pm at 201" of Oct 8:
/// read in 2.9 s, held until the owner resumed entries, sent at a $201.00 limit while PM was
/// offered at $208.86, and cancelled unfilled a minute later.
@MainActor
func runActivityTimelineTests() throws {
    try theTimelineShowsEveryStepWithItsGap()
    try aFilledBuyEndsFilledWithItsTimeToFill()
    try anUnfilledBuySaysWhyItWasCancelled()
    try otherCancelsNameTheirCause()
}

private func pmOrder() -> [String: Any] {
    [
        "client_id": "copy-1", "symbol": "PM", "side": "buy", "status": "canceled", "quantity": "0.995024",
        "filled_quantity": "0", "limit_price": "201.00", "average_fill_price": NSNull(), "broker_id": "b1",
        "created_at": "2026-10-08T17:03:04.182Z", "instruction_index": 0, "requested_usd": "600",
        "budget_usd": "200", "order_type": "limit", "session": "regular", "source_price": "201",
        "entry_tolerance_pct": "0", "submitted_at": "2026-10-08T17:03:04.198Z", "quote_bid": "201.49",
        "quote_ask": "208.86", "cancel_reason": "timeout", "ended_at": "2026-10-08T17:04:07.090Z",
    ]
}

private func step(_ name: String, _ at: String, reason: String? = nil, quantity: String? = nil, price: String? = nil)
    -> [String: Any]
{
    [
        "step": name, "at": at, "client_id": name == "received" || name == "held" || name == "resumed" ? NSNull() : "copy-1",
        "reason": reason ?? NSNull(), "quantity": quantity ?? NSNull(), "price": price ?? NSNull(),
    ]
}

private func pm() throws -> SourceActivity {
    try SourceActivityBuilder()
        .text("buy pm at 201")
        .posted(at: "2026-10-08T17:02:40.113Z")
        .read(started: "2026-10-08T17:02:40.436Z", finished: "2026-10-08T17:02:43.329Z", delivered: "2026-10-08T17:02:43.536Z")
        .calls([SourceActivityBuilder.buy("PM", "201")])
        .destination(
            "primary", status: "done", outcomes: ["order_linked"], orders: [pmOrder()],
            timeline: [
                step("received", "2026-10-08T17:02:43.367Z"),
                step("held", "2026-10-08T17:02:43.367Z", reason: "waiting_for_resume"),
                step("resumed", "2026-10-08T17:03:01.321Z"),
                step("sized", "2026-10-08T17:03:04.182Z", quantity: "0.995024", price: "201.00"),
                step("sent", "2026-10-08T17:03:04.198Z"),
                step("accepted", "2026-10-08T17:03:04.320Z"),
                step("cancel_requested", "2026-10-08T17:04:07.090Z", reason: "timeout"),
                step("cancelled", "2026-10-08T17:04:07.090Z"),
            ]
        )
        .build()
}

@MainActor
private func theTimelineShowsEveryStepWithItsGap() throws {
    let timeline = PostTimeline(try pm())
    let titles = timeline.phases.map(\.title)
    try #require(titles == ["Received", "Read", "Sent", "Cancelled · not filled in time"], "phases were \(titles)")
    let read = timeline.phases[1]
    try #require(read.detail == "deepseek-flash · 2.9 s", "read detail \(read.detail ?? "nil")")
    try #require(read.duration.map(PostTimeline.duration) == "3.2 s", "read took \(read.duration ?? -1)")
    let sent = timeline.phases[2]
    try #require(
        sent.detail == "0.995024 PM, limit $201.00 · accepted by Alpaca in 0.12 s", "sent detail \(sent.detail ?? "nil")")
    try #require(sent.waits == ["Held 18 s waiting for you to resume"], "sent waits \(sent.waits)")
    let ended = timeline.phases[3]
    try #require(ended.waits == ["Waited 1 min 2 s for a fill"], "ended waits \(ended.waits)")
    try #require(ended.detail == nil, "the full reason belongs on the card, not the timeline")
    try #require(ended.caution, "an unfilled order reads as a caution")
    try #require(
        !timeline.phases.compactMap(\.duration).contains { $0 < PostTimeline.measurable }, "no phase may show a zero gap")
    try #require(timeline.phases[0].duration == nil, "the first phase has no time before it")
    try #require(timeline.toOrder.map(PostTimeline.duration) == "24 s", "post to order \(timeline.toOrder ?? -1)")
    try #require(timeline.toFill == nil, "an unfilled order has no time to fill")
}

@MainActor
private func aFilledBuyEndsFilledWithItsTimeToFill() throws {
    var order = pmOrder()
    order["status"] = "filled"
    order["filled_quantity"] = "0.995024"
    order["average_fill_price"] = "200.82"
    order["cancel_reason"] = NSNull()
    let source = try SourceActivityBuilder()
        .posted(at: "2026-10-08T17:02:40.113Z")
        .read(started: "2026-10-08T17:02:40.436Z", finished: "2026-10-08T17:02:43.329Z", delivered: "2026-10-08T17:02:43.536Z")
        .destination(
            "primary", status: "done", outcomes: ["order_linked"], orders: [order],
            timeline: [
                step("received", "2026-10-08T17:02:43.536Z"),
                step("sized", "2026-10-08T17:02:43.600Z", quantity: "0.995024", price: "201.00"),
                step("sent", "2026-10-08T17:02:43.610Z"),
                step("accepted", "2026-10-08T17:02:43.700Z"),
                step("filled", "2026-10-08T17:02:44.900Z", quantity: "0.995024", price: "200.82"),
            ]
        )
        .build()
    let timeline = PostTimeline(source)
    try #require(timeline.phases.map(\.title) == ["Received", "Read", "Sent", "Filled"], "phases \(timeline.phases.map(\.title))")
    try #require(timeline.phases[3].detail == "0.995024 PM at $200.82", "fill detail \(timeline.phases[3].detail ?? "nil")")
    try #require(timeline.phases[2].waits.isEmpty && !timeline.phases[3].caution)
    try #require(timeline.toFill.map(PostTimeline.duration) == "4.8 s", "post to fill \(timeline.toFill ?? -1)")
}

@MainActor
private func anUnfilledBuySaysWhyItWasCancelled() throws {
    let source = try pm()
    let expected =
        "Not filled within 1 min 2 s at your limit of $201.00. PM was offered at $208.86 when it went out. "
        + "Your buys pay at most the guru's price, so it waited for the price to come down."
    let sentence = CancelReasonText.sentence(try #require(source.destinations.first?.orders.first))
    try #require(sentence == expected, "reason was \(sentence ?? "nil")")
    let line = try #require(ActivityCardOutcome(source, skipped: false).accounts.first?.lines.first)
    try #require(line.why?.hasPrefix(expected) == true, "the card said \(line.why ?? "nil")")
    try #require(line.why?.hasSuffix("Your max per order cut it to $200.") == true, "the trim note went missing")
}

@MainActor
private func otherCancelsNameTheirCause() throws {
    func reason(_ code: String) throws -> String? {
        var changed = pmOrder()
        changed["cancel_reason"] = code
        let source = try SourceActivityBuilder().destination("primary", status: "done", orders: [changed]).build()
        return CancelReasonText.sentence(try #require(source.destinations.first?.orders.first))
    }
    try #require(try reason("replaced_by_sell") == "Cancelled because the guru sold PM before it filled.")
    try #require(try reason("copying_stopped") == "Cancelled when copying stopped, before it filled.")
    try #require(try reason("cancelled_at_broker") == "Cancelled at Alpaca, not by CopyTrading.")
    try #require(try reason("expired") == "Expired when the trading day ended, unfilled.")
}
