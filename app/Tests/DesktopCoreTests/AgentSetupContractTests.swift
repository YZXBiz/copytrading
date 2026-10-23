import Foundation
@testable import DesktopCore
import Testing

/// The app reads every setup request the CLI sends, answers in the contract's shapes, and asks
/// the engine about them without their keys.
func runAgentSetupContractTests() throws {
    try everySetupRequestTheCLISendsDecodes()
    try badSetupRequestsAreRefusedWithoutTheirKeys()
    try setupResponsesMatchTheContract()
    try theEngineIsAskedWithoutKeys()
}

private func requestLines() throws -> [String] {
    let object = try JSONSerialization.jsonObject(with: contractFixture("agent-setup-requests.json"))
    guard let requests = (object as? [String: Any])?["requests"] as? [Any] else {
        throw VerificationFailure(description: "the setup request fixture has no requests")
    }
    return try requests.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
}

private func everySetupRequestTheCLISendsDecodes() throws {
    var decoded: [AgentSetupRequest] = []
    for line in try requestLines() {
        do {
            decoded.append(try AgentSetupRequest(line: line))
        } catch {
            throw VerificationFailure(description: "a CLI setup request did not decode: \(error.message)")
        }
    }
    try #require(
        Set(decoded.map(\.operation)) == Set(AgentSetupOperation.allCases), "every setup operation needs a fixture")
    try #require(decoded.map(\.requestID).first == "s1", "the request ID must come through")
    guard case .discord(let discord) = decoded[1].edit else {
        throw VerificationFailure(description: "the Discord edit did not decode as one")
    }
    try #require(
        discord.channelIDs == ["111", "222"] && discord.authorIDs == [] && discord.token?.value == "test-discord-token",
        "the Discord edit lost a field")
    try #require(
        !String(describing: discord).contains("test-discord-token")
            && !String(reflecting: decoded[1]).contains("test-discord-token"),
        "a decoded token must never print")
    guard case .account(let account) = decoded[3].edit else {
        throw VerificationFailure(description: "the account edit did not decode as one")
    }
    try #require(
        account.action == .add && account.accountID == "paper-2" && account.environment == .paper
            && account.key?.value == "PKTESTKEY" && account.secret?.value == "test-secret"
            && account.limits == [
                AgentLimitChange(field: "max_order_usd", value: "250"), AgentLimitChange(field: "overnight", value: "true"),
            ] && account.recoveryPreference == .automatic,
        "the account edit lost a field")
    guard case .guru(let guru) = decoded[6].edit else {
        throw VerificationFailure(description: "the guru edit did not decode as one")
    }
    try #require(
        guru.guru == "Alex" && guru.channelID == "111" && guru.authorID == "" && guru.accountID == "paper-2"
            && guru.fullPositionUSD == "600" && guru.repeatWindowMinutes == 0,
        "the guru edit lost a field")
    guard case .importText(let text) = decoded[10].edit else {
        throw VerificationFailure(description: "the import did not decode as one")
    }
    try #require(text.value.hasPrefix("Discord token:"), "the import lost its text")
    try #require(
        AgentSetupOperation.of(line: #"{"operation":"get_status"}"#) == nil
            && AgentSetupOperation.of(line: "not json") == nil
            && AgentSetupOperation.of(line: #"{"operation":"apply_setup"}"#) == .apply,
        "only setup lines may go to the app's setup handler")
}

private func badSetupRequestsAreRefusedWithoutTheirKeys() throws {
    let cases: [(String, String)] = [
        (
            #"{"schema_version":1,"request_id":"b1","operation":"edit_setup_account","action":"edit","account_id":"paper","key":"leaked-key"}"#,
            "together"
        ),
        (
            #"{"schema_version":1,"request_id":"b2","operation":"edit_setup_account","action":"add","account_id":"bad name"}"#,
            "account name"
        ),
        (#"{"schema_version":1,"request_id":"b3","operation":"edit_setup_discord","channel_ids":["general"]}"#, "digits"),
        (#"{"schema_version":1,"request_id":"b4","operation":"edit_setup_model"}"#, "at least one"),
        (
            #"{"schema_version":1,"request_id":"b5","operation":"edit_setup_account","action":"edit","account_id":"a","limits":[{"field":"api_key","value":"leaked-key"}]}"#,
            "not an account setting"
        ),
        (#"{"schema_version":1,"request_id":"b6","operation":"edit_setup_model","service":"skynet"}"#, "no model service"),
        (
            #"{"schema_version":1,"request_id":"b7","operation":"edit_setup_account","action":"edit","account_id":"a","recovery_preference":"resume"}"#,
            "After a restart"
        ),
    ]
    for (line, expected) in cases {
        do {
            _ = try AgentSetupRequest(line: line)
            throw VerificationFailure(description: "a bad setup request was accepted: \(expected)")
        } catch let error as AgentSetupRequestError {
            try #require(
                error.message.contains(expected) && !error.message.contains("leaked-key") && !error.requestID.isEmpty,
                "a bad setup request was refused as \(error.message)")
        }
    }
}

private func setupResponsesMatchTheContract() throws {
    let object = try JSONSerialization.jsonObject(with: contractFixture("agent-setup-responses.json"))
    guard let expected = (object as? [String: Any])?["responses"] as? [NSDictionary], expected.count == 3 else {
        throw VerificationFailure(description: "the setup response fixture lost its responses")
    }
    let failed = AgentSetupCheck(
        connection: .account, subject: "zhap-account-2", state: .failed, reason: "broker_auth_or_permissions_failed",
        message:
            "zhap-account-2: Alpaca didn't accept these keys. Check that they are for a paper or live account as chosen."
    )
    let passed = AgentSetupCheck(connection: .discord, subject: nil, state: .passed, reason: nil, message: nil)
    let view = AgentSetupView(
        saved: true, unsavedChanges: true, copying: "copying",
        discord: .init(channelIDs: ["111"], authorIDs: [], token: .saved, check: passed),
        model: .init(service: "ollama", model: "qwen3", baseURL: "http://localhost:11434/v1", key: .notNeeded, check: nil),
        accounts: [
            .init(
                accountID: "zhap-account-2", environment: .paper, keys: .entered,
                limits: [
                    AgentLimitChange(field: "max_order_usd", value: "100"),
                    AgentLimitChange(field: "overnight", value: "false"),
                ], recoveryPreference: .automatic, check: failed)
        ],
        gurus: [
            .init(
                guruID: GuruIdentity.id(channelID: "111"), name: "Alex", channelID: "111", authorID: nil, accountID: "zhap-account-2",
                fullPositionUSD: "600", repeatWindowMinutes: 10, playbookCharacters: 0)
        ],
        alerts: .init(enabled: false, service: .telegram, chatID: nil, token: .missing, check: nil))
    let lines = [
        AgentSetupResponse.line(requestID: "s1", result: .setup(view)),
        AgentSetupResponse.line(
            requestID: "s12",
            result: .applied(
                AgentSetupApplied(
                    status: .failedChecks, message: "Some connections need attention. Nothing was saved.",
                    checks: [passed, failed]))),
        AgentSetupResponse.errorLine(
            requestID: "s13", code: "not_found",
            message:
                "There is no account called paper-9 in the setup. Add it with `copytrading setup account add paper-9`, or see the names with `copytrading setup show`."
        ),
    ]
    for (line, fixture) in zip(lines, expected) {
        let sent = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? NSDictionary
        try #require(sent == fixture, "the app's setup response differs from the contract: \(line)")
    }
}

private func theEngineIsAskedWithoutKeys() throws {
    let request = EngineRequest(
        requestID: "req-authorize-setup-request",
        operation: .authorizeSetup(
            AgentSetupAuthorizationRequest(
                operation: .apply, requestID: "s12",
                apply: AgentSetupApplyFacts(madeLive: ["live-1"], newLiveKeys: ["live-1"], startsLive: ["live-1"])),
            context: AgentRequestContext(
                accessLevel: .propose, unlocked: true, callerPID: 4242, callerPath: "/usr/bin/agent",
                setupChanges: true)))
    let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary
    let expected = try JSONSerialization.jsonObject(with: contractFixture("authorize-setup-request.json")) as? NSDictionary
    try #require(sent != nil && sent == expected, "the app's setup authorization differs: \(String(describing: sent))")
    let allowed = try JSONDecoder().decode(EngineResponse.self, from: contractFixture("setup-allowed-response.json"))
    guard case .setupAllowed = try allowed.successValue() else {
        throw VerificationFailure(description: "an allowed setup request did not decode as allowed")
    }
    let proposal = try JSONDecoder().decode(
        AgentProposal.self,
        from: Data(
            """
            {"proposal_id":"p-0123456789ab","state":"pending","digest":"\(String(repeating: "0", count: 64))",\
            "command_id":"agent-1","created_at":"2026-10-23T15:00:00Z","expires_at":"2026-10-23T15:05:00Z",\
            "requested_by":{"pid":4242,"path":"/usr/bin/agent"},"outcome":null,\
            "subject":{"kind":"apply_setup","made_live":["live-1"],"new_live_keys":[],"changed_live":[],"starts_live":["live-1"]}}
            """.utf8))
    try #require(
        proposal.subject == .applySetup(AgentSetupApplyFacts(madeLive: ["live-1"], startsLive: ["live-1"])),
        "an apply proposal must keep what it does to live accounts")
}
