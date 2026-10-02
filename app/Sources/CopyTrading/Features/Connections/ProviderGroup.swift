import DesktopCore

/// How Connections groups the interpreters: the familiar ones first, then the rest of the hosted
/// services, then the ones the owner runs.
enum ProviderGroup: CaseIterable, Identifiable {
    case popular
    case more
    case ownModel

    var id: Self { self }

    @MainActor var title: String {
        switch self {
        case .popular: L10n.string("Popular")
        case .more: L10n.string("More Providers")
        case .ownModel: L10n.string("Your Own Model")
        }
    }

    var providers: [TradingProviderName] {
        switch self {
        case .popular: [.anthropic, .openai, .google, .deepseek]
        case .more: [.openrouter, .groq, .xai, .mistral, .together, .fireworks, .cerebras, .moonshotai]
        case .ownModel: [.ollama, .openAICompatible]
        }
    }
}
