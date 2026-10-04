import DesktopCore
import Foundation

/// Where each interpreter's key comes from, and the model name its field suggests.
extension SetupHelp {
    @MainActor
    static var interpreters: [HelpArticle] { TradingProviderName.allCases.map(interpreterKey(for:)) }

    @MainActor
    static func interpreterKey(for provider: TradingProviderName) -> HelpArticle {
        switch provider {
        case .ollama:
            HelpArticle(
                id: "interpreter.ollama",
                title: "Run a model with Ollama",
                intro:
                    "Ollama runs the model on this Mac, so posts never leave it and nothing is billed. Reading posts well takes a capable model and a fast Mac.",
                steps: [
                    "Install **Ollama** and open it.",
                    "In Terminal, run **ollama pull llama3.2**, or pull any model you prefer.",
                    "Enter that model's name under **Model**. Leave **Base URL** and **API key** empty: CopyTrading finds Ollama at its usual address on this Mac.",
                ],
                destination: .init(title: "Download Ollama", url: URL(literal: "https://ollama.com/download"))
            )
        case .openAICompatible:
            HelpArticle(
                id: "interpreter.openai_compatible",
                title: "Use any OpenAI-compatible service",
                intro:
                    "Many services and local servers, such as LM Studio, vLLM, and LiteLLM, answer the same way OpenAI does. CopyTrading can read posts through any of them.",
                steps: [
                    "Find the service's base URL. It usually ends in **/v1**.",
                    "Enter it under **Base URL**. It must start with **https://**, or **http://** for a server on this Mac.",
                    "Enter the model's name under **Model**, and a key under **API key** if the service asks for one.",
                ],
                destination: .init(
                    title: "The OpenAI API it must speak", url: URL(literal: "https://platform.openai.com/docs/api-reference/chat"))
            )
        default:
            hostedKey(for: provider)
        }
    }

    /// The model name a provider's field suggests.
    @MainActor
    static func modelExample(for provider: TradingProviderName) -> String {
        L10n.string("e.g. %@", suggestedModel(for: provider))
    }

    /// What the Model field starts with: the provider's recommended model, or nothing for a custom
    /// service, whose models CopyTrading can't know.
    @MainActor
    static func prefilledModel(for provider: TradingProviderName) -> String? {
        provider == .openAICompatible ? nil : suggestedModel(for: provider)
    }

    @MainActor
    static func suggestedModel(for provider: TradingProviderName) -> String {
        switch provider {
        case .anthropic: "claude-sonnet-5-5"
        case .openai: "gpt-5.5-mini"
        case .google: "gemini-2.5-flash"
        case .deepseek: "deepseek-flash"
        case .openrouter: "anthropic/claude-sonnet-5.5"
        case .groq: "llama-3.3-70b-versatile"
        case .xai: "grok-4"
        case .mistral: "mistral-large-latest"
        case .together: "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        case .fireworks: "accounts/fireworks/models/llama-v3p3-70b-instruct"
        case .cerebras: "llama-3.3-70b"
        case .moonshotai: "kimi-k2"
        case .ollama: "llama3.2"
        case .openAICompatible: L10n.string("your model's name")
        }
    }

    /// A hosted service: sign in to its console, make a key, and paste it with a model name.
    @MainActor
    private static func hostedKey(for provider: TradingProviderName) -> HelpArticle {
        let console = console(for: provider)
        let reach =
            provider == .openrouter
            ? "OpenRouter reaches hundreds of models from many makers with one key, and bills your account for what they read."
            : L10n.string(
                "The interpreter is the AI model that reads each post. %@ bills your account for what it reads.",
                provider.title
            )
        return HelpArticle(
            id: "interpreter.\(provider.rawValue)",
            title: L10n.string("Get %@ %@ API key", L10n.string(article(before: provider.title)), provider.title),
            intro: reach,
            steps: [
                L10n.string("Sign in at **%@** and open **%@**.", console.site, L10n.string(console.page)),
                L10n.string("Create a key, name it CopyTrading, and copy it. Most services show a key only once."),
                L10n.string(
                    "Paste it into **API key**, and enter a model name such as **%@** under **Model**.",
                    suggestedModel(for: provider)
                ),
            ],
            destination: .init(title: L10n.string("Open %@ API keys", provider.title), url: console.url)
        )
    }

    private static func console(for provider: TradingProviderName) -> (site: String, page: String, url: URL) {
        switch provider {
        case .anthropic: ("platform.claude.com", "API Keys", URL(literal: "https://platform.claude.com/settings/keys"))
        case .openai: ("platform.openai.com", "API keys", URL(literal: "https://platform.openai.com/api-keys"))
        case .google: ("aistudio.google.com", "Get API key", URL(literal: "https://aistudio.google.com/apikey"))
        case .deepseek: ("platform.deepseek.com", "API keys", URL(literal: "https://platform.deepseek.com/api_keys"))
        case .openrouter: ("openrouter.ai", "Keys", URL(literal: "https://openrouter.ai/settings/keys"))
        case .groq: ("console.groq.com", "API Keys", URL(literal: "https://console.groq.com/keys"))
        case .xai: ("console.x.ai", "API Keys", URL(literal: "https://console.x.ai"))
        case .mistral: ("console.mistral.ai", "API Keys", URL(literal: "https://console.mistral.ai/api-keys"))
        case .together: ("api.together.ai", "API Keys", URL(literal: "https://api.together.ai/settings/api-keys"))
        case .fireworks: ("fireworks.ai", "API Keys", URL(literal: "https://fireworks.ai/account/api-keys"))
        case .cerebras: ("cloud.cerebras.ai", "API Keys", URL(literal: "https://cloud.cerebras.ai"))
        case .moonshotai: ("platform.moonshot.ai", "API Keys", URL(literal: "https://platform.moonshot.ai/console/api-keys"))
        case .ollama, .openAICompatible: ("", "", URL(literal: "https://ollama.com"))
        }
    }

    /// "an" before a vowel sound as these names are said: an OpenAI key, an xAI key.
    private static func article(before name: String) -> String {
        ["A", "E", "I", "O", "U", "x"].contains(where: name.hasPrefix) ? "an" : "a"
    }
}
