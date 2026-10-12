import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// Each copied order is announced once when it goes out and once when it fills; what was sent or
/// filled before the app opened is never announced, but the first read after opening still says
/// what happened since.
@MainActor
func runFillWatchTests() throws {
    let opened = ISO8601DateFormatter().date(from: "2026-10-12T14:30:00Z")!
    func order(_ id: String, _ status: String, at stamp: String) -> [String: Any] {
        [
            "client_id": id, "symbol": "WMT", "side": "buy", "status": status, "quantity": "1",
            "filled_quantity": status == "filled" ? "1" : "0", "limit_price": "110", "average_fill_price": "110.75",
            "broker_id": "b-\(id)", "created_at": stamp, "submitted_at": stamp,
            "ended_at": status == "filled" ? stamp : NSNull(), "instruction_index": 0,
        ]
    }
    func post(_ orders: [[String: Any]]) throws -> SourceActivity {
        try SourceActivityBuilder().decision("trade", reason: "Bought")
            .calls([SourceActivityBuilder.buy("WMT", "110", fraction: nil)])
            .destination("primary", status: "done", outcomes: ["order_linked"], orders: orders)
            .build()
    }
    let before = "2026-10-12T14:00:00Z"
    let after = "2026-10-12T14:31:00.250Z"

    var watch = FillWatch(openedAt: opened)
    let first = try watch.news(in: [
        post([
            order("old", "filled", at: before), order("oldOpen", "new", at: before),
            order("justFilled", "filled", at: after), order("prepared", "prepared", at: after),
        ])
    ])
    try #require(first.filled.map(\.clientID) == ["justFilled"], "first read announced \(first.filled.map(\.clientID))")
    try #require(first.sent.isEmpty, "an order from before the app opened, or not yet sent, was announced as sent")
    try #require(first.filled.first?.price == Decimal(string: "110.75"), "the fill lost its price")

    let sent = try watch.news(in: [post([order("live", "accepted", at: after)])])
    try #require(sent.sent.map(\.clientID) == ["live"] && sent.filled.isEmpty, "a sent order was not announced once")
    try #require(sent.sent.first?.price == Decimal(110), "a sent order did not carry its limit")

    let filled = try watch.news(in: [post([order("live", "filled", at: after), order("justFilled", "filled", at: after)])])
    try #require(filled.filled.map(\.clientID) == ["live"] && filled.sent.isEmpty, "the fill was not announced once")
    try #require(try watch.news(in: [post([order("live", "filled", at: after)])]).isEmpty, "a fill was announced twice")
    print("CopyTradingContractTests: each copied order is announced once when sent and once when filled, never from before the app opened")
}
