import Foundation
@testable import DesktopCore
import Testing

/// The app sends exactly the assistant requests the engine's fixtures describe, and reads its replies.
func runAssistantContractTests() throws {
    try verifySameJSON(
        EngineRequest(
            requestID: "req-assistant-ask-request",
            operation: .assistantAsk(
                conversationID: "c-0123456789ab",
                text: "Why was the last call skipped?",
                context: AssistantAskContext(
                    screen: "accounts", language: "en", gurus: [AssistantGuru(id: "guru-1a2b3c4d", name: "Zhao")]),
                provider: TradingProviderConfiguration(name: .deepseek, model: "deepseek-flash"),
                providerAPIKey: "test-only")),
        as: "assistant-ask-request.json")
    let chinese = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(
            AssistantAskContext(
                screen: "people", selectedGuruID: "guru-1a2b3c4d", language: "zh-Hans",
                gurus: [AssistantGuru(id: "guru-1a2b3c4d", name: "赵老师")])))
    try #require(
        (chinese as? [String: Any])?["language"] as? String == "zh-Hans",
        "an ask in 简体中文 did not send its language: \(chinese)")
    try #require(
        ((chinese as? [String: Any])?["gurus"] as? [[String: String]]) == [["id": "guru-1a2b3c4d", "name": "赵老师"]],
        "an ask did not name its gurus: \(chinese)")
    let many = (0..<60).map { AssistantGuru(id: "guru-\($0)", name: "Guru \($0)") }
    try #require(
        AssistantAskContext(screen: "people", gurus: many).gurus.count == AssistantAskContext.maxGurus,
        "an ask sent more gurus than the engine reads")
    try verifySameJSON(
        EngineRequest(
            requestID: "req-assistant-turn-request",
            operation: .assistantTurn(turnID: "t-0123456789ab", after: 0)),
        as: "assistant-turn-request.json")

    guard case .assistantTurnStarted(let turnID) = try decodeResult("assistant-ask-response.json") else {
        throw VerificationFailure(description: "an assistant ask reply did not decode as a started turn")
    }
    try #require(turnID == "t-0123456789ab", "a started turn lost its id")

    guard case .assistantTurn(let page) = try decodeResult("assistant-turn-response.json") else {
        throw VerificationFailure(description: "an assistant turn reply did not decode as a turn page")
    }
    try #require(page.turnID == "t-0123456789ab" && !page.done, "a turn page lost its id or done flag")
    try #require(page.events.count == 1, "a turn page lost its events")
    try #require(
        page.events[0].seq == 1 && page.events[0].kind == .step
            && page.events[0].text == "Looked at your accounts",
        "an assistant event lost its sequence, kind, or text")
    try #require(
        page.events[0].link == nil && page.events[0].proposalID == nil && page.events[0].code == nil,
        "an assistant event invented a link, proposal, or code")

    let linked = try JSONDecoder().decode(
        AssistantEvent.self,
        from: Data(
            #"{"seq":2,"kind":"link","text":null,"link":{"kind":"guru","id":"g1","title":"Ana"},"proposal_id":null,"code":null}"#
                .utf8))
    try #require(linked.link == AssistantLink(kind: "guru", id: "g1", title: "Ana"), "an assistant link did not decode")
    let proposed = try JSONDecoder().decode(
        AssistantEvent.self,
        from: Data(#"{"seq":3,"kind":"proposal","text":null,"link":null,"proposal_id":"p-1","code":null}"#.utf8))
    try #require(proposed.proposalID == "p-1", "an assistant proposal event lost its proposal id")

    guard case .assistantCancelled(let cancelled) = try decodeResult("assistant-cancel-response.json") else {
        throw VerificationFailure(description: "an assistant cancel reply did not decode as one")
    }
    try #require(cancelled, "an assistant cancel reply lost its flag")
    guard case .assistantReset = try decodeResult("assistant-reset-response.json") else {
        throw VerificationFailure(description: "an assistant reset reply did not decode as one")
    }
}

private func decodeResult(_ fixture: String) throws -> EngineResult {
    try JSONDecoder().decode(EngineResponse.self, from: contractFixture(fixture)).successValue()
}

private func verifySameJSON(_ request: EngineRequest, as fixture: String) throws {
    let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary
    let expected = try JSONSerialization.jsonObject(with: contractFixture(fixture)) as? NSDictionary
    try #require(sent != nil && sent == expected, "the app's request differs from \(fixture): \(String(describing: sent))")
}
