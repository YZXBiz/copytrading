import Foundation
@testable import DesktopCore
import Testing

func runProtocolFixtureTests() throws {
    try checkAccountValuationFixturesDecode()
    try checkLotSaleFixtures()
    let completed = try JSONDecoder().decode(
        EngineResponse.self,
        from: contractFixture("completed-self-test.json")
    )
    guard case .workflow(let workflow) = try completed.successValue() else {
        throw VerificationFailure(description: "completed self-test returned a non-workflow result")
    }
    try #require(workflow.commandID == "sim-1", "completed workflow command ID changed")
    try #require(workflow.outcomes.count == 2, "completed workflow lost a destination outcome")
    try #require(
        workflow.outcomes.allSatisfy { $0.result == .simulated },
        "workflow outcomes must remain explicitly simulated"
    )

    let failed = try JSONDecoder().decode(
        EngineResponse.self,
        from: contractFixture("failed-self-test.json")
    )
    guard case .workflow(let failedWorkflow) = try failed.successValue() else {
        throw VerificationFailure(description: "failed self-test returned a non-workflow result")
    }
    try #require(failedWorkflow.stage == .failed, "failed self-test was not decoded as failed")
    try #require(failedWorkflow.outcomes.isEmpty, "failed self-test must not invent outcomes")

    let statusResponse = try JSONDecoder().decode(
        EngineResponse.self,
        from: contractFixture("status-response.json")
    )
    guard case .status(let status) = try statusResponse.successValue() else {
        throw VerificationFailure(description: "status fixture returned a non-status result")
    }
    try #require(status.instanceID == "installation-1", "status installation identity changed")
    try #require(status.state == .running, "engine running state did not decode")
    try #require(status.telemetryState == .degraded, "degraded telemetry state did not decode")
    try #require(status.telemetryDropped == 2, "telemetry drop count did not decode")
    try #require(
        status.telemetryErrorCode == "queue_full",
        "typed journal error did not decode")
    try #require(
        status.diagnosticCapture.sourceEventGaps == 1,
        "diagnostic capture gaps did not decode")

    let backup = try JSONDecoder().decode(
        EngineResponse.self,
        from: Data(
            #"""
            {"version":1,"request_id":"backup-1","ok":{"type":"backup","manifest":{"format":"copytrading-backup","format_version":1,"created_at":"2026-09-27T12:00:00+00:00","installation_id":"source-install","environment_ids":["paper:acct-a"],"members":[{"path":"application.db","size":64,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":"sqlite:application:2;components="}]}}}
            """#.utf8))
    guard case .backup(let manifest) = try backup.successValue() else {
        throw VerificationFailure(description: "backup response returned the wrong result type")
    }
    try #require(manifest.members.first?.path == "application.db", "backup manifest lost SQLite member")

    let restore = try JSONDecoder().decode(
        EngineResponse.self,
        from: Data(
            #"""
            {"version":1,"request_id":"restore-1","ok":{"type":"restore_preview","preview":{"format_version":1,"created_at":"2026-09-27T12:00:00+00:00","installation_id":"source-install","matches_installation":false,"environment_ids":["paper:acct-a"],"account_ids":["acct-a"],"credential_references":["00000000-0000-4000-8000-000000000000"],"staging_id":"restore-abcd","members":[{"path":"application.db","size":64,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":"sqlite:application:2;components="}]}}}
            """#.utf8))
    guard case .restorePreview(let preview) = try restore.successValue() else {
        throw VerificationFailure(description: "restore response returned the wrong result type")
    }
    try #require(
        !preview.matchesInstallation && preview.credentialReferences.count == 1,
        "restore preview lost identity or credential-reference requirements")

    let preflight = try JSONDecoder().decode(
        EngineResponse.self,
        from: Data(
            #"""
            {"version":1,"request_id":"restore-preflight-1","ok":{"type":"restore_preflight","candidate_id":"00000000-0000-4000-8000-000000000001","eligible":false,"checked_account_count":1,"blockers":["broker_state_mismatch"],"completion_token":null}}
            """#.utf8))
    guard case .restorePreflight(let preflightView) = try preflight.successValue() else {
        throw VerificationFailure(description: "restore preflight response returned the wrong result type")
    }
    try #require(
        preflightView.blockers == ["broker_state_mismatch"] && preflightView.completionToken == nil,
        "restore preflight lost a blocker or exposed a completion token on failure")

    let recovery = try JSONDecoder().decode(
        EngineResponse.self,
        from: Data(
            #"""
            {"version":1,"request_id":"restore-status-1","ok":{"type":"restore_candidate_status","candidate":{"candidate_id":"00000000-0000-4000-8000-000000000001","previous_generation":"00000000-0000-4000-8000-000000000002","active_generation":"00000000-0000-4000-8000-000000000002","installation_id":"00000000-0000-4000-8000-000000000003","environment_ids":["paper:acct-a"],"account_ids":["acct-a"],"credential_references":["00000000-0000-4000-8000-000000000004"],"candidate_valid":true}}}
            """#.utf8))
    guard case .restoreCandidateStatus(let pending) = try recovery.successValue() else {
        throw VerificationFailure(description: "restore status response returned the wrong result type")
    }
    try #require(
        pending?.candidateID == "00000000-0000-4000-8000-000000000001"
            && pending?.activeGeneration == pending?.previousGeneration,
        "restore status lost its durable rollback evidence")

    let activated = try JSONDecoder().decode(
        EngineResponse.self,
        from: Data(
            #"""
            {"version":1,"request_id":"restore-activated-1","ok":{"type":"restore_activated","candidate_id":"00000000-0000-4000-8000-000000000001"}}
            """#.utf8))
    guard case .restoreActivated(let activatedID) = try activated.successValue() else {
        throw VerificationFailure(description: "restore completion response returned the wrong result type")
    }
    try #require(
        activatedID == "00000000-0000-4000-8000-000000000001",
        "restore completion response lost the candidate identity")

    let unknownVersion = try JSONDecoder().decode(
        EngineResponse.self,
        from: contractFixture("unknown-version.json")
    )
    try verifyThrows(
        { _ = try unknownVersion.successValue() },
        matching: { $0 as? EngineContractError == .unsupportedVersion(2) },
        "unknown protocol version must not become a success"
    )

    try verifyThrows(
        {
            _ = try JSONDecoder().decode(
                EngineResponse.self,
                from: contractFixture("malformed.json")
            )
        },
        matching: { $0 is DecodingError },
        "malformed shared fixture must fail JSON decoding"
    )
}

/// The app sends exactly the lot sale requests the engine's fixtures describe, and reads its replies.
private func checkLotSaleFixtures() throws {
    let lotID = "copy-0123456789abcdef0123456789abcdef01234567"
    try verifySameJSON(
        EngineRequest(
            requestID: "req-lot-sale-preview",
            operation: .previewLotSale(
                LotSalePreviewRequest(previewID: "lot-sale-preview-1", accountID: "paper", lotID: lotID, quantity: "2"))),
        as: "lot-sale-preview-request.json")
    try verifySameJSON(
        EngineRequest(
            requestID: "req-lot-sale",
            operation: .confirmLotSale(
                LotSaleConfirmation(commandID: "lot-sale-1", previewID: "lot-sale-preview-1", accountID: "paper", actor: "owner"))),
        as: "lot-sale-confirm-request.json")

    let previewResponse = try JSONDecoder().decode(EngineResponse.self, from: contractFixture("lot-sale-preview-response.json"))
    guard case .lotSalePreview(let preview) = try previewResponse.successValue() else {
        throw VerificationFailure(description: "a lot sale preview did not decode as one")
    }
    try #require(preview.plan?.lotID == lotID && preview.plan?.type == "limit", "a lot sale plan lost its lot or order type")
    try #require(preview.freshPrice == "26.10" && preview.reasons.isEmpty, "a lot sale preview lost its price or reasons")

    let saleResponse = try JSONDecoder().decode(EngineResponse.self, from: contractFixture("lot-sale-response.json"))
    guard case .lotSale(let sale) = try saleResponse.successValue() else {
        throw VerificationFailure(description: "a lot sale result did not decode as one")
    }
    try #require(sale.status == "filled" && sale.filledQty == "2", "a lot sale result lost its fill")
    try #require(sale.sale.lotID == lotID, "a lot sale result lost its lot")
}

private func verifySameJSON(_ request: EngineRequest, as fixture: String) throws {
    let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary
    let expected = try JSONSerialization.jsonObject(with: contractFixture(fixture)) as? NSDictionary
    try #require(sent != nil && sent == expected, "the app's request differs from \(fixture): \(String(describing: sent))")
}

private func checkAccountValuationFixturesDecode() throws {
    let accounts = try JSONDecoder().decode(
        EngineResponse.self, from: contractFixture("account-overviews-response.json")
    )
    guard case .accounts(let page) = try accounts.successValue(), let balance = page.items.first?.balance else {
        throw VerificationFailure(description: "account overview lost its balance")
    }
    try #require(balance.equity == "25412.80", "equity changed while decoding")
    try #require(balance.dayChangeUSD == "412.80", "day change changed while decoding")
    try #require(balance.observedAt == "2026-09-26T14:59:58Z", "balance time changed while decoding")
    guard let lot = page.items.first?.positions.first?.lots.first else {
        throw VerificationFailure(description: "account overview lost its position's lots")
    }
    try #require(lot.sourceID == "discord:demo:1", "a lot lost the post that bought it")
    try #require(lot.remainingQty == "2" && lot.averagePrice == "25.10", "a lot's shares or price changed while decoding")
    try #require(page.items.first?.positions.first?.currentPrice == nil, "an unread broker produced a price")

    // A position the broker valued: cost, price, value, and gain, for the position and its lot.
    let valued = try JSONDecoder().decode(
        AccountPositionView.self,
        from: Data(
            """
            {"symbol":"PM","owned_qty":"1","external_qty":"0","broker_qty":"1",
             "avg_entry_price":"199.59","current_price":"200.96","market_value":"200.96",
             "unrealized_pl":"1.37","unrealized_plpc":"0.0069",
             "lots":[{"lot_id":"l1","source_id":null,"guru_id":null,"posted_at":null,"excerpt":null,
               "bought_at":null,"original_qty":"1","remaining_qty":"1","average_price":"199.59",
               "unrealized_pl":"1.37"}]}
            """.utf8))
    try #require(valued.avgEntryPrice == "199.59" && valued.currentPrice == "200.96", "a position's prices did not decode")
    try #require(valued.marketValue == "200.96" && valued.unrealizedPL == "1.37", "a position's value or gain did not decode")
    try #require(valued.unrealizedPLPercent == "0.0069", "a position's gain percent did not decode")
    try #require(valued.lots.first?.unrealizedPL == "1.37", "a lot's gain did not decode")

    let activity = try JSONDecoder().decode(
        EngineResponse.self, from: contractFixture("manual-source-activity-response.json")
    )
    guard case .sourceActivity(let sources) = try activity.successValue(),
        let order = sources.items.flatMap(\.destinations).flatMap(\.orders).first
    else {
        throw VerificationFailure(description: "source activity lost its orders")
    }
    try #require(order.averageFillPrice == "12.30", "average fill price did not decode")
    try #require(order.limitPrice == "12.34", "limit price did not decode")

    let history = try JSONDecoder().decode(
        EngineResponse.self, from: contractFixture("equity-history-response.json")
    )
    guard case .equityHistory(let accountID, let curve?) = try history.successValue() else {
        throw VerificationFailure(description: "equity history did not decode")
    }
    try #require(
        accountID == "paper" && curve.window == EquityHistoryWindow(range: .day, day: "2026-09-26"),
        "equity history identity changed"
    )
    try #require(curve.points.count == 4 && curve.points.last?.equity == "25412.8", "equity points changed")

    let request = try JSONEncoder().encode(
        EngineRequest(
            requestID: "req-history",
            operation: .equityHistory(accountID: "paper", window: EquityHistoryWindow(range: .threeMonths))
        )
    )
    let object = try JSONSerialization.jsonObject(with: request) as? [String: Any]
    try #require(object?["operation"] as? String == "get_equity_history", "history operation name changed")
    let window = object?["window"] as? [String: Any]
    try #require(
        window?["range"] as? String == "three_months" && window?["day"] == nil,
        "history window did not encode"
    )
}
