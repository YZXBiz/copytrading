import Foundation

/// Names the program behind an agent request the way the owner thinks of it.
enum AgentCallerName {
    /// The caller name the engine's assistant puts on its control requests.
    static let assistant = "CopyTrading Assistant"

    static func isAssistant(_ path: String?) -> Bool { path == assistant }

    /// The `copytrading` command and MCP server run on the app's own Python, so that
    /// executable stands for them rather than for an arbitrary script.
    @MainActor
    static func describe(_ path: String?, bundle: Bundle = .main) -> String {
        guard let path else { return L10n.string("An unknown program") }
        if isAssistant(path) { return L10n.string(assistant) }
        let runtime = bundle.bundleURL.appending(path: "Contents/Resources/Runtime").path + "/"
        if path.hasPrefix(runtime) { return L10n.string("copytrading command") }
        return URL(filePath: path).lastPathComponent
    }
}
