import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// A fill is announced once, the first time it is read; what was filled before the app opened is
/// never announced, and an order that is still open is not a fill.
@MainActor
func runFillWatchTests() throws {
    func order(_ id: String, _ status: String) -> [String: Any] {
        [
            "client_id": id, "symbol": "WMT", "side": "buy", "status": status, "quantity": "1",
            "filled_quantity": status == "filled" ? "1" : "0", "limit_price": "110", "average_fill_price": "110.75",
            "broker_id": "b-\(id)", "created_at": "2026-10-09T14:30:01Z", "instruction_index": 0,
        ]
    }
    func post(_ orders: [[String: Any]]) throws -> SourceActivity {
        try SourceActivityBuilder().decision("trade", reason: "Bought")
            .calls([SourceActivityBuilder.buy("WMT", "110", fraction: nil)])
            .destination("primary", status: "done", outcomes: ["order_linked"], orders: orders)
            .build()
    }

    var watch = FillWatch()
    try #require(try watch.newFills(in: [post([order("old", "filled")])]).isEmpty, "a fill from before the app opened was announced")
    let fills = try watch.newFills(in: [post([order("old", "filled"), order("new", "filled"), order("open", "new")])])
    try #require(fills.map(\.clientID) == ["new"], "announced \(fills.map(\.clientID)) instead of the one new fill")
    try #require(
        fills.first?.accountID == "primary" && fills.first?.price == Decimal(string: "110.75"), "the fill lost its account or price")
    try #require(try watch.newFills(in: [post([order("new", "filled")])]).isEmpty, "a fill was announced twice")
    print("CopyTradingContractTests: each fill is announced once, and never one from before the app opened")
}
