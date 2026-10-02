import DesktopCore
import Foundation

/// The assistant answers "how do I set this up" from the engine's own help text, which ships in
/// the bundled engine. Every article the app shows must be in it, or the two drift apart.
@MainActor
func runAssistantHelpTests() throws {
    guard let root = ProcessInfo.processInfo.environment["COPYTRADING_ENGINE_ROOT"] else {
        throw AssistantHelpFailure(description: "COPYTRADING_ENGINE_ROOT is not set, so the bundled assistant help cannot be checked")
    }
    let help = URL(filePath: root, directoryHint: .isDirectory)
        .appending(path: "src/copytrading_engine/assistant/help.md")
    guard let text = try? String(contentsOf: help, encoding: .utf8) else {
        throw AssistantHelpFailure(description: "The bundled engine has no assistant help at \(help.path)")
    }
    let missing = SetupHelp.all.map(\.title).filter { !text.contains($0) }
    guard missing.isEmpty else {
        throw AssistantHelpFailure(description: "The assistant help is missing the app's help articles: \(missing)")
    }
    print("CopyTradingContractTests: assistant help covers all \(SetupHelp.all.count) app help articles")
}

private struct AssistantHelpFailure: Error, CustomStringConvertible {
    let description: String
}
