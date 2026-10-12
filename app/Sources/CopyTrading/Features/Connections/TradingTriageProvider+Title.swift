import DesktopCore

extension TradingTriageProvider {
    /// The company behind the decision model, as the owner knows it: "Sorted by OpenAI".
    var title: String {
        switch self {
        case .openAIDecisions: "OpenAI"
        case .typeSafe: "TypeSafe"
        }
    }

    /// The logo Connections shows beside it, from the app's brand icons.
    var brand: String? {
        switch self {
        case .openAIDecisions: "openai"
        case .typeSafe: nil
        }
    }
}
