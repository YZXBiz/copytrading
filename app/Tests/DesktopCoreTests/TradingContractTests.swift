import DesktopCore
import Foundation
import Testing

func runTradingContractTests() throws {
    try capabilityChecksCarryAModelSuggestion()
    try alertsNameTheirService()
    let profile = try TradingProfileBuilder().build(
        TradingProfileDraft(
            guruID: "stable-guru", displayName: "Stable Guru",
            exitBasis: .originalPosition
        ))
    let configuration = TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["123"], authorIDs: ["456"]),
        provider: TradingProviderConfiguration(name: .anthropic, model: "test-model"),
        accounts: [TradingAccountConfiguration(id: "paper-a", environment: .paper)],
        profiles: [profile],
        routes: [
            TradingRouteConfiguration(
                channelID: "123", authorID: "456", guruID: profile.guruID,
                profileRevision: profile.profileRevision,
                connections: [
                    TradingRouteConnection(accountID: "paper-a", fullPositionUSD: "3000")
                ]
            )
        ]
    )
    let encoded = try JSONEncoder().encode(configuration)
    let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    try #require(json?["source"] != nil, "trading configuration omitted its source")
    try #require(
        String(decoding: encoded, as: UTF8.self).contains("channel_ids"),
        "trading configuration lost the engine snake-case contract"
    )
    try #require(
        !String(decoding: encoded, as: UTF8.self).contains("token"),
        "saved trading configuration unexpectedly contains a credential field"
    )
    try #require(configuration.version == 7, "profile configuration did not use v7")
    try #require(
        profile.profileRevision == "f9d0063f8729dadeb2d80ed607b2e38a9966fa8afdc40495f1b8f2b73a3cf74d",
        "native content address differs from the engine profile builder")
    let exampleProfile = try TradingProfileBuilder().build(
        TradingProfileDraft(
            guruID: "zhao", displayName: "Zhao", playbook: "Apple means AAPL",
            examples: [
                TradingProfileExample(
                    message: "ALERT: Bought Apple at 200 1/6", expectedAction: .buy,
                    expectedSymbol: "AAPL", expectedFraction: "0.1666666666666666666666666667"
                )
            ],
            exitBasis: .originalPosition
        ))
    try #require(
        exampleProfile.profileRevision == "265a667b20c8327f426a52011879bc1d38d91c89caf7b77ec80e998241e0b4b9",
        "native profile examples do not use the engine canonical revision format")
    // A learned playbook is multi-line Chinese with quotes, tabs, and slashes: every one of those
    // must hash exactly as the engine hashes it, or activation would stall on a revision mismatch.
    let chineseProfile = try TradingProfileBuilder().build(
        TradingProfileDraft(
            guruID: "zhao", displayName: "赵哥",
            playbook: "加了 means buy\n英伟达 means NVDA\n\"quoted\" words, a\ttab, and a / slash",
            exitBasis: .remainingPosition
        ))
    try #require(
        chineseProfile.profileRevision == "12c1a3884b59797dc374cd45aa6063ed96eb7932ac7361f024b73ebcd20e2026",
        "a multi-line Chinese playbook does not hash to the engine's revision")
    do {
        _ = try TradingProfileBuilder().build(
            TradingProfileDraft(
                guruID: "zhao", displayName: "Zhao",
                playbook: String(repeating: "x", count: tradingPlaybookMaxLength + 1),
                exitBasis: .originalPosition
            ))
        throw VerificationFailure(description: "a playbook over the engine's limit was accepted")
    } catch TradingProfileBuilderError.invalidProfile {}
    let rulesProfile = try TradingProfileBuilder().build(
        TradingProfileDraft(
            guruID: "analyst", displayName: "分析师", exitBasis: .originalPosition,
            batches: 3, sellsReferTo: .wholePosition
        ))
    try #require(
        rulesProfile.profileRevision == "366a3a180b01e2d3235567697fc190275d90081609828e48b18ee713a86e52f4",
        "a guru's batches and sell rule do not hash to the engine's revision")
    try sizingMatchesTheEngineOnEverySharedExample()
    let prepared = try TradingProfileBuilder().preparedProfiles()
    try #require(
        prepared.map(\.exitBasis) == [.originalPosition, .remainingPosition],
        "prepared profile conventions changed")
    let learned = Data(
        """
        {"version":1,"request_id":"learn-1","ok":{"type":"learned_playbook","playbook":{
        "posts_read":80,"exit_basis":"original_position",
        "playbook":"加了 means buy","examples":[{"message":"赵哥-股票： 25加了abc",
        "expected_action":"buy","expected_symbol":"ABC","expected_fraction":null}],
        "summary":"Buys lead with the price.","provider":"deepseek","model":"deepseek-flash",
        "cost_notice":"Model calls use the configured provider; provider charges may apply."}}}
        """.utf8)
    guard
        case .learnedPlaybook(let draft) = try JSONDecoder().decode(
            EngineResponse.self, from: learned
        ).successValue()
    else {
        throw VerificationFailure(description: "a learned playbook did not decode as a learned result")
    }
    try #require(
        draft.postsRead == 80 && draft.examples.count == 1,
        "a learned playbook lost its fields")

    try runTradingConfigurationPersistenceTests()

    let response = Data(
        """
        {"version":1,"request_id":"trade-1","ok":{"type":"trading_status","trading":\
        {"state":"paused","configured_accounts":1,"active_accounts":0,"source_connected":false,\
        "model_ready":false,"pending_source":0,"pending_signals":0,"processed_signals":0,"error_code":null,\
        "accounts":[{"id":"paper-a","state":"paused","error_code":null}]}}}
        """.utf8)
    guard
        case .trading(let status) = try JSONDecoder().decode(
            EngineResponse.self, from: response
        ).successValue()
    else {
        throw VerificationFailure(description: "trading status did not decode as a trading result")
    }
    try #require(status.state == .paused, "trading status lost manual resume state")
    try #require(status.accounts.first?.id == "paper-a", "trading account status was lost")

    let activationID = "00112233-4455-6677-8899-aabbccddeeff"
    let activationResponse = Data(
        """
        {"version":1,"request_id":"activation-1","ok":{"type":"trading_activation","activation":{
        "requested_activation_id":"\(activationID)","activation_id":"\(activationID)",
        "candidate_revision":"\(String(repeating: "a", count: 64))",
        "committed_revision":"\(String(repeating: "a", count: 64))",
        "committed_activation_id":"\(activationID)","phase":"stopped",
        "runtime_state":"paused","error_code":null}}}
        """.utf8)
    guard
        case .tradingActivation(let activation) = try JSONDecoder().decode(
            EngineResponse.self, from: activationResponse
        ).successValue()
    else {
        throw VerificationFailure(description: "activation evidence did not decode as an activation result")
    }
    try #require(
        activation.committedActivationID == activationID,
        "activation status lost its activation-specific commit evidence")
}

/// A missing model comes back with the nearest name the provider lists; other checks carry none.
private func capabilityChecksCarryAModelSuggestion() throws {
    let json = Data(
        """
        {"name":"model","state":"failed","subject":null,"environment":null,"identity":null,\
        "adapter":"deepseek","reason_code":"model_not_found","suggestion":"deepseek-flash"}
        """.utf8)
    let check = try JSONDecoder().decode(TradingCapabilityCheck.self, from: json)
    try #require(check.reasonCode == "model_not_found" && check.suggestion == "deepseek-flash")
    let older = Data(#"{"name":"model","state":"ready","adapter":"deepseek","reason_code":null}"#.utf8)
    try #require(try JSONDecoder().decode(TradingCapabilityCheck.self, from: older).suggestion == nil)
}

/// Discord alerts carry no chat ID; a saved setup from before Discord reads as Telegram.
private func alertsNameTheirService() throws {
    let discord = try JSONEncoder().encode(TradingNotificationConfiguration(service: .discord, chatID: "42"))
    let fields = try JSONSerialization.jsonObject(with: discord) as? [String: Any]
    try #require(fields?["service"] as? String == "discord" && fields?["chat_id"] == nil)
    let telegram = try JSONDecoder().decode(TradingNotificationConfiguration.self, from: Data(#"{"chat_id":"42"}"#.utf8))
    try #require(telegram.service == .telegram && telegram.chatID == "42")
}

private struct SizingExamples: Decodable {
    struct Fraction: Decodable {
        let numerator: Int
        let denominator: Int
    }

    struct Example: Decodable {
        let `case`: String
        let fullPositionUSD: String
        let fraction: Fraction?
        let budgetUSD: String?

        enum CodingKeys: String, CodingKey {
            case `case`
            case fullPositionUSD = "full_position_usd"
            case fraction
            case budgetUSD = "budget_usd"
        }
    }

    let examples: [Example]
}

/// The app's sizing examples come from its own copy of the engine's rule; the engine runs the same
/// examples in `test_sizing_contract.py`.
private func sizingMatchesTheEngineOnEverySharedExample() throws {
    let examples = try JSONDecoder().decode(
        SizingExamples.self, from: contractFixture("sizing-examples.json")
    ).examples
    try #require(!examples.isEmpty, "no shared sizing examples")
    for example in examples {
        let connection = TradingRouteConnection(accountID: "paper", fullPositionUSD: example.fullPositionUSD)
        let source = example.fraction.map { Decimal($0.numerator) / Decimal($0.denominator) }
        let budget = connection.copiedBudgetUSD(sourceFraction: source)
        try #require(
            budget == example.budgetUSD.flatMap { Decimal(string: $0) },
            "sizing differs from the engine: \(example.case) gave \(String(describing: budget))")
    }
}
