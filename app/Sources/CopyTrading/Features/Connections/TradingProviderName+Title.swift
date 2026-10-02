import DesktopCore

extension TradingProviderName {
    /// The provider's name as the provider writes it.
    var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .google: "Google Gemini"
        case .deepseek: "DeepSeek"
        case .openrouter: "OpenRouter"
        case .groq: "Groq"
        case .xai: "xAI"
        case .mistral: "Mistral"
        case .together: "Together AI"
        case .fireworks: "Fireworks AI"
        case .cerebras: "Cerebras"
        case .moonshotai: "Moonshot AI (Kimi)"
        case .ollama: "Ollama (on this Mac)"
        case .openAICompatible: "Other (OpenAI-compatible)"
        }
    }

    /// The name where space is short: a tile, or a panel's serif title.
    var shortTitle: String {
        switch self {
        case .moonshotai: "Moonshot AI"
        case .ollama: "Ollama"
        case .openAICompatible: "OpenAI-compatible"
        default: title
        }
    }

    /// One line on what reading posts with it means.
    @MainActor var tagline: String {
        switch self {
        case .anthropic: L10n.string("Claude models")
        case .openai: L10n.string("GPT models")
        case .google: L10n.string("Gemini models")
        case .deepseek: L10n.string("DeepSeek models, at a low price")
        case .openrouter: L10n.string("Hundreds of models with one key")
        case .groq: L10n.string("Open models, answered very fast")
        case .xai: L10n.string("Grok models")
        case .mistral: L10n.string("Mistral models")
        case .together: L10n.string("Open models, hosted for you")
        case .fireworks: L10n.string("Open models, hosted for you")
        case .cerebras: L10n.string("Open models, answered very fast")
        case .moonshotai: L10n.string("Kimi models")
        case .ollama: L10n.string("A model on this Mac, with no key and no bill")
        case .openAICompatible: L10n.string("Any service or server that speaks the OpenAI API")
        }
    }
}
