import Foundation

/// Where the chat filter's key comes from (ADR-0012).
extension SetupHelp {
    static let chatFilterKey = HelpArticle(
        id: "chatFilter.openai",
        title: "Get an OpenAI API key",
        intro:
            "OpenAI's decision model sorts each post before the interpreter reads it. Small talk it is sure of is skipped; everything else is read as before.",
        steps: [
            "Sign in at **platform.openai.com** and open **API keys**.",
            "Create a key, name it CopyTrading, and copy it. Most services show a key only once.",
            "Paste it into **OpenAI key**. OpenAI bills your account, about 15¢ per 1,000 posts.",
        ],
        destination: .init(title: "Open OpenAI API keys", url: URL(literal: "https://platform.openai.com/api-keys"))
    )
}
