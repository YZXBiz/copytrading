import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// A post in flight shows the step it is on with its running time; a settled post shows none, so
/// nothing ticks; and Activity is read every second only while something is in flight.
@MainActor
func runLiveStepTests() throws {
    try aPostBeingReadSaysSoWithItsModel()
    try anOrderAtTheBrokerCountsAgainstItsTimeout()
    try aHeldBuyNamesItsResumeDeadline()
    try aSettledPostHasNoLiveStep()
    try activityIsReadEverySecondOnlyWhileSomethingIsInFlight()
    try aFastReadKeepsOlderPagesLoaded()
}

private let posted = "2026-10-08T17:02:40.000Z"

private func at(_ seconds: TimeInterval) throws -> Date {
    try #require(Humanize.date(posted)).addingTimeInterval(seconds)
}

private func order(status: String) -> [String: Any] {
    [
        "client_id": "copy-1", "symbol": "PM", "side": "buy", "status": status, "quantity": "0.995024",
        "filled_quantity": "0", "limit_price": "201.00", "average_fill_price": NSNull(), "broker_id": "b1",
        "created_at": "2026-10-08T17:02:44.000Z", "instruction_index": 0, "requested_usd": "600",
        "budget_usd": "200", "submitted_at": "2026-10-08T17:02:44.000Z",
    ]
}

private func step(_ name: String, _ at: String) -> [String: Any] {
    ["step": name, "at": at, "client_id": NSNull(), "reason": NSNull(), "quantity": NSNull(), "price": NSNull()]
}

@MainActor
private func aPostBeingReadSaysSoWithItsModel() throws {
    let item = try SourceActivityBuilder().posted(at: posted).decision(nil)
        .inFlight(parse: "pending", delivery: "not_ready", readStarted: "2026-10-08T17:02:40.300Z")
        .build()
    let progress = try #require(PostProgress(item, context: .init(readerModel: "deepseek-flash")))
    #expect(progress.step == .reading(model: "deepseek-flash"))
    #expect(progress.line(at: try at(2.4)) == "Reading with deepseek-flash… 2 s")
    #expect(progress.short(at: try at(2.4)) == "Reading · 2 s")
    #expect(!progress.isSlow(at: try at(2.4)))
    #expect(progress.isSlow(at: try at(6)))
}

@MainActor
private func anOrderAtTheBrokerCountsAgainstItsTimeout() throws {
    let item = try SourceActivityBuilder().posted(at: posted)
        .read(started: posted, finished: "2026-10-08T17:02:43.000Z", delivered: "2026-10-08T17:02:43.200Z")
        .destination("primary", status: "queued", orders: [order(status: "accepted")])
        .build()
    let progress = try #require(PostProgress(item, context: .init(orderTimeouts: ["primary": 60])))
    #expect(PostProgress.live(125) == "2 min 5 s")
    #expect(progress.step == .awaitingFill(account: "primary", symbol: "PM", timeout: 60))
    #expect(progress.line(at: try at(16)) == "Sent to Alpaca · waiting for a fill · 12 s of 60 s")
    #expect(progress.short(at: try at(16)) == "Waiting for fill · 12 s")
    #expect(progress.isSlow(at: try at(40)))
}

@MainActor
private func aHeldBuyNamesItsResumeDeadline() throws {
    let item = try SourceActivityBuilder().posted(at: posted)
        .read(started: posted, finished: "2026-10-08T17:02:43.000Z", delivered: "2026-10-08T17:02:43.200Z")
        .destination(
            "primary", status: "queued",
            timeline: [step("received", "2026-10-08T17:02:43.300Z"), step("held", "2026-10-08T17:02:43.300Z")]
        )
        .build()
    let deadline = try at(120)
    let progress = try #require(PostProgress(item, resume: ResumeWait(deadlines: ["primary": deadline])))
    #expect(progress.step == .heldForResume(account: "primary", copiesUntil: deadline))
    #expect(progress.short(at: try at(11.3)) == "Held for you · 8 s")
    #expect(progress.isSlow(at: try at(4)), "a hold waits on the owner, so it always reads as a caution")
}

@MainActor
private func aSettledPostHasNoLiveStep() throws {
    let filled = try SourceActivityBuilder().posted(at: posted)
        .read(started: posted, finished: "2026-10-08T17:02:43.000Z", delivered: "2026-10-08T17:02:43.200Z")
        .destination("primary", status: "done", orders: [order(status: "filled")])
        .build()
    let ignored = try SourceActivityBuilder().posted(at: posted).decision("ignore").build()
    let review = try SourceActivityBuilder().posted(at: posted).decision("review").build()
    for item in [filled, ignored, review] {
        #expect(PostProgress(item) == nil, "a settled post must not tick")
    }
}

@MainActor
private func activityIsReadEverySecondOnlyWhileSomethingIsInFlight() throws {
    let settled = try SourceActivityBuilder().posted(at: posted).decision("ignore").build()
    let reading = try SourceActivityBuilder().sequence(2, sourceID: "discord:1:3").posted(at: posted).decision(nil)
        .inFlight(parse: "pending", delivery: "not_ready").build()
    #expect(ActivityRefreshCadence.interval(for: [settled]) == 15)
    #expect(ActivityRefreshCadence.interval(for: []) == 15)
    #expect(ActivityRefreshCadence.interval(for: [reading, settled]) == 1)
}

@MainActor
private func aFastReadKeepsOlderPagesLoaded() throws {
    func post(_ sequence: Int) throws -> SourceActivity {
        try SourceActivityBuilder().sequence(sequence, sourceID: "discord:1:\(sequence)").posted(at: posted).build()
    }
    let loaded = try [5, 4, 3, 2, 1].map(post)
    let newest = try [6, 5, 4].map(post)
    #expect(AccountFeatureModel.merged(newest, into: loaded).map(\.id) == [6, 5, 4, 3, 2, 1])
    #expect(AccountFeatureModel.merged([], into: loaded).map(\.id) == [5, 4, 3, 2, 1])
}
