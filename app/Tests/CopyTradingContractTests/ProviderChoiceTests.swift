import DesktopCore
import Foundation
import Testing

/// Choosing an interpreter: a base URL travels only for a provider that takes one, a local model
/// needs no key, and a key saved for one provider is never sent to another.
@MainActor
func runProviderChoiceTests() throws {
    var draft = ConnectionsDraft()
    draft.modelName = "gpt-5.5-mini"
    draft.provider = .openai
    draft.providerBaseURL = "https://ignored.example.com/v1"
    try #require(draft.providerConfiguration.baseURL == nil, "a fixed-address provider kept a typed base URL")

    draft.provider = .ollama
    draft.providerBaseURL = "  "
    try #require(draft.providerConfiguration.baseURL == nil, "a blank Ollama address was sent")
    try #require(draft.providerConfiguration.baseURLProblem == nil, "Ollama needed an address")
    try #require(progress(draft).done.contains(.interpreter), "a local model without a key did not tick the step")

    draft.provider = .openAICompatible
    try #require(draft.providerConfiguration.baseURLProblem != nil, "an endpoint was accepted without an address")
    try #require(!progress(draft).done.contains(.interpreter), "the step ticked before the endpoint had an address")
    draft.providerBaseURL = "http://models.example.com/v1"
    try #require(draft.providerConfiguration.baseURLProblem != nil, "plain http to another machine was accepted")
    draft.providerBaseURL = " http://localhost:1234/v1 "
    try #require(draft.providerConfiguration.baseURL == "http://localhost:1234/v1", "the address was not trimmed")
    try #require(progress(draft).done.contains(.interpreter), "a local endpoint without a key did not tick the step")

    draft.provider = .deepseek
    try #require(!progress(draft).done.contains(.interpreter), "a hosted provider ticked without a key")

    let saved = try savedSetup(
        provider: TradingProviderConfiguration(
            name: .openAICompatible, model: "local", baseURL: "https://models.example.com/v1"))
    var reloaded = ConnectionsDraft()
    reloaded.load(saved.configuration)
    try #require(
        reloaded.provider == .openAICompatible && reloaded.providerBaseURL == "https://models.example.com/v1",
        "the saved endpoint did not come back into the draft")

    try #require(
        AppModel.providerKey(entered: "", for: .openAICompatible, saved: saved) == "saved-key",
        "the saved key was not kept for its own provider")
    try #require(
        AppModel.providerKey(entered: "", for: .openai, saved: saved).isEmpty,
        "a key saved for one provider was offered to another")
    try #require(
        AppModel.providerKey(entered: "typed", for: .openai, saved: saved) == "typed", "a typed key was not used")
    print("CopyTradingContractTests: interpreters carry an address only where it belongs, and keys stay with their provider")
}

@MainActor
private func progress(_ draft: ConnectionsDraft) -> SetupProgress {
    SetupProgress(draft: draft, hasSavedKeys: false, hasSavedProviderKey: false, savedKeyAccountIDs: [], isSetUp: false)
}

private func savedSetup(
    provider: TradingProviderConfiguration
) throws -> (configuration: TradingConfiguration, secrets: TradingSecrets) {
    let profile = try TradingProfileBuilder().build(
        TradingProfileDraft(guruID: "alex", displayName: "Alex", prefix: "ALERT:", exitBasis: .originalPosition))
    let configuration = TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["123"]),
        provider: provider,
        accounts: [TradingAccountConfiguration(id: "paper", environment: .paper)],
        profiles: [profile],
        routes: [
            TradingRouteConfiguration(
                channelID: "123", authorID: nil, guruID: "alex", profileRevision: profile.profileRevision,
                connections: [TradingRouteConnection(accountID: "paper", fullPositionUSD: "600", defaultFraction: nil)])
        ]
    )
    let secrets = TradingSecrets(
        discordToken: "token", providerAPIKey: "saved-key",
        brokers: [TradingBrokerCredentials(accountID: "paper", key: "k", secret: "s")], notificationToken: nil)
    return (configuration, secrets)
}
