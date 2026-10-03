import DesktopCore
import Foundation
import Testing

/// The provider names and the base URL travel exactly as the engine reads them, and the rules
/// for keys and addresses match the engine's.
func runTradingProviderContractTests() throws {
    try #require(
        TradingProviderName.allCases.map(\.rawValue) == [
            "anthropic", "openai", "google", "deepseek", "openrouter", "groq", "xai", "mistral",
            "together", "fireworks", "cerebras", "moonshotai", "ollama", "openai_compatible",
        ],
        "provider wire names or their order changed")

    let hosted = try JSONEncoder().encode(TradingProviderConfiguration(name: .openai, model: "gpt-5.5-mini"))
    try #require(
        !String(decoding: hosted, as: UTF8.self).contains("base_url"),
        "a provider without an address encoded a base_url")
    let custom = TradingProviderConfiguration(
        name: .openAICompatible, model: "local", baseURL: "https://models.example.com/v1")
    let encoded = try JSONEncoder().encode(custom)
    let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    try #require(json?["base_url"] as? String == "https://models.example.com/v1", "base_url was not encoded")
    try #require(json?["name"] as? String == "openai_compatible", "openai_compatible lost its wire name")
    let decoded = try JSONDecoder().decode(TradingProviderConfiguration.self, from: encoded)
    try #require(decoded == custom, "provider configuration did not round-trip")

    try #require(
        TradingProviderName.allCases.filter { !$0.requiresAPIKey } == [.ollama, .openAICompatible],
        "only local providers may go without an API key")
    try #require(
        TradingProviderConfiguration(name: .openAICompatible, model: "m").baseURLProblem != nil,
        "an OpenAI-compatible provider was accepted without a base URL")
    try #require(
        TradingProviderConfiguration(name: .ollama, model: "llama3.2").baseURLProblem == nil,
        "Ollama required a base URL")
    try #require(
        TradingProviderConfiguration(name: .openai, model: "m", baseURL: "https://api.openai.com/v1").baseURLProblem
            != nil,
        "a fixed-address provider accepted a base URL")
    for allowed in ["https://api.example.com/v1", "http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://[::1]:8080/v1"] {
        try #require(TradingProviderConfiguration.isAllowedBaseURL(allowed), "\(allowed) was refused")
    }
    for refused in ["http://models.example.com/v1", "ftp://localhost/v1", "localhost:11434", "https://user:pass@example.com/v1", ""] {
        try #require(!TradingProviderConfiguration.isAllowedBaseURL(refused), "\(refused) was allowed")
    }
}
