import DesktopCore
import Foundation

func runCommandJournalTests() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "command-journal-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "commands.json")
    let command = SelfTestCommand(
        commandID: UUID().uuidString.lowercased(), text: "Bought AAPL 1/6 at 200", destinationIDs: ["self-test-a", "self-test-b"])
    let journal = CommandJournal(url: url)
    try await journal.record(command)
    let restored = try await CommandJournal(url: url).entries()
    try verify(restored.count == 1 && restored[0].command == command, "crash lost the command envelope before engine submission")
    try verify(restored[0].workflow == nil, "unsent command was marked complete")
    try await journal.record(command)
    let repeated = try await journal.entries()
    try verify(repeated.count == 1, "retrying same command created a second activity entry")

    let workflowData = Data(
        """
        {"command_id":"\(command.commandID)","stage":"completed","outcomes":[{"account_id":"self-test-a","result":"simulated"},{"account_id":"self-test-b","result":"simulated"}],"trace_id":"30000000-0000-4000-8000-000000000003"}
        """.utf8)
    let workflow = try JSONDecoder().decode(WorkflowView.self, from: workflowData)
    try await journal.record(workflow)
    let afterCompletion = try await CommandJournal(url: url).entries()
    try verify(
        afterCompletion.count == 1 && afterCompletion[0].workflow == workflow, "completed workflow was not durably visible after relaunch")
    let stalePayload = Data(
        """
        {"command_id":"\(command.commandID)","stage":"captured","outcomes":[],"trace_id":"30000000-0000-4000-8000-000000000003"}
        """.utf8)
    try await journal.record(JSONDecoder().decode(WorkflowView.self, from: stalePayload))
    let afterStaleReply = try await journal.entries()
    try verify(afterStaleReply[0].workflow == workflow, "a stale IPC reply downgraded completed Activity history")
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    try verify(permissions?.intValue == 0o600, "command journal was not private")
}
