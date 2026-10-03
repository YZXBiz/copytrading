import DesktopCore
import Foundation
import Testing

@MainActor
func runLotSaleFlowTests() async throws {
    try await paperSalesNeedNoTouchIDAndSendTheReviewedPreview()
    try await liveSalesAskForTouchIDAndSendNothingWithoutIt()
    try await aRetryAfterALostConnectionReusesTheSaleIdentity()
    print("CopyTradingContractTests: lot sales review first, ask for Touch ID on live accounts, and never send twice")
}

private actor FakeLotSales: LotSaleOperations {
    var previews: [LotSalePreviewRequest] = []
    var confirmations: [LotSaleConfirmation] = []
    var failNextConfirmation = false

    func previewLotSale(_ preview: LotSalePreviewRequest) async throws -> LotSalePreview {
        previews.append(preview)
        return try JSONDecoder().decode(
            LotSalePreview.self,
            from: Data(
                """
                {"request":{"preview_id":"\(preview.previewID)","account_id":"\(preview.accountID)","lot_id":"\(preview.lotID)","qty":"\(preview.quantity)"},\
                "broker_account_id":"broker","environment":"paper","symbol":"ABC","lot_remaining_qty":"12",\
                "created_at":"2026-09-26T15:00:03Z","expires_at":"2026-09-26T15:00:33Z","session":"regular",\
                "quote":{"feed":"iex","bid":"26.10","ask":"26.12","timestamp":"2026-09-26T15:00:02Z"},"fresh_price":"26.10",\
                "plan":{"side":"sell","position_intent":"sell_to_close","type":"market","limit_price":null,"symbol":"ABC",\
                "qty":"\(preview.quantity)","source_price":"26.10","entry_tolerance_pct":"0","lot_id":"\(preview.lotID)",\
                "entry_price":"25.10","session":"regular"},"checks":[],"reasons":[],\
                "facts_sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}
                """.utf8))
    }

    func confirmLotSale(_ sale: LotSaleConfirmation) async throws -> LotSaleResult {
        confirmations.append(sale)
        if failNextConfirmation {
            failNextConfirmation = false
            throw URLError(.networkConnectionLost)
        }
        return try JSONDecoder().decode(
            LotSaleResult.self,
            from: Data(
                """
                {"sale":{"request":{"command_id":"\(sale.commandID)","preview_id":"\(sale.previewID)","account_id":"\(sale.accountID)",\
                "actor":"owner"},"lot_id":"copy-lot","confirmed_at":"2026-09-26T15:00:10Z","state":"prepared","reason":null,\
                "client_id":"lotsale-1"},"status":"filled","reason":null,"client_id":"lotsale-1","broker_order_id":"b-1",\
                "order_status":"filled","filled_qty":"12","filled_avg_price":"26.08"}
                """.utf8))
    }

    func failNext() { failNextConfirmation = true }
}

@MainActor
private func target(_ environment: TradingEnvironment) throws -> LotSaleTarget {
    let lot = try JSONDecoder().decode(
        AccountLotView.self,
        from: Data(
            """
            {"lot_id":"copy-lot","source_id":"discord:demo:1","guru_id":"alex","posted_at":"2026-09-26T14:30:00Z",\
            "excerpt":"ABC long here","bought_at":"2026-09-26T14:30:05Z","original_qty":"12","remaining_qty":"12",\
            "average_price":"25.10"}
            """.utf8))
    return LotSaleTarget(accountID: "primary", environment: environment, symbol: "ABC", lot: lot, guruName: "Alex")
}

@MainActor
private func paperSalesNeedNoTouchIDAndSendTheReviewedPreview() async throws {
    let sales = FakeLotSales()
    let flow = LotSaleFlow(target: try target(.paper))
    try #require(flow.shares == 12, "A sale did not start with the whole lot")
    flow.shares = 5
    await flow.review(using: sales)
    guard case .reviewing(let preview) = flow.phase else { throw saleFailure("Review did not show a preview") }
    let previews = await sales.previews
    try #require(previews.first?.quantity == "5" && previews.first?.lotID == "copy-lot", "Review asked for the wrong shares")
    var asked = false
    await flow.confirm(using: sales) { asked = true }
    try #require(!asked, "A paper sale asked for Touch ID")
    guard case .finished(let result) = flow.phase else { throw saleFailure("Confirming did not finish the sale") }
    let confirmations = await sales.confirmations
    try #require(confirmations.first?.previewID == preview.request.previewID, "Sell sent a different preview")
    try #require(result.status == "filled", "The sale result was lost")
}

@MainActor
private func liveSalesAskForTouchIDAndSendNothingWithoutIt() async throws {
    let sales = FakeLotSales()
    let flow = LotSaleFlow(target: try target(.live))
    await flow.review(using: sales)
    await flow.confirm(using: sales) { throw CancellationError() }
    let refused = await sales.confirmations
    try #require(refused.isEmpty, "A live sale went out without Touch ID")
    guard case .reviewing = flow.phase, flow.problem != nil else { throw saleFailure("A refused Touch ID did not explain itself") }
    var asked = false
    await flow.confirm(using: sales) { asked = true }
    let sent = await sales.confirmations
    try #require(asked && sent.count == 1, "A confirmed live sale did not go out once")
}

@MainActor
private func aRetryAfterALostConnectionReusesTheSaleIdentity() async throws {
    let sales = FakeLotSales()
    let flow = LotSaleFlow(target: try target(.paper))
    await flow.review(using: sales)
    await sales.failNext()
    await flow.confirm(using: sales) {}
    guard case .reviewing = flow.phase else { throw saleFailure("A lost connection did not return to the review") }
    await flow.confirm(using: sales) {}
    let confirmations = await sales.confirmations
    try #require(
        confirmations.count == 2 && confirmations[0].commandID == confirmations[1].commandID,
        "A retry used a new sale identity, so the engine could place the sale twice")
    flow.startOver()
    await flow.review(using: sales)
    await flow.confirm(using: sales) {}
    let afterStartOver = await sales.confirmations
    try #require(afterStartOver.last?.commandID != confirmations[0].commandID, "Starting over kept the old sale identity")
}

private func saleFailure(_ message: String) -> NSError {
    NSError(domain: "LotSaleFlowTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
