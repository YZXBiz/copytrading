import DesktopCore
import Foundation
import Testing

func runDiagnosticsJournalTests() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "copytrading-journal-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try settingsRoundTripAndRejectUnsupportedValues(root)
    try journalReadsNewestFirstAcrossRotations(root)
    try journalSkipsDamagedLinesAndReadsPayloads(root)
}

private func settingsRoundTripAndRejectUnsupportedValues(_ root: URL) throws {
    let store = DiagnosticsSettingsStore(url: root.appending(path: "settings/settings.json"))
    let missing = try store.load()
    try #require(missing == nil, "missing settings must read as nothing saved")
    let chosen = try DiagnosticsSettings(ageDays: 30, storageLimitBytes: 512 * 1_024 * 1_024)
    try store.save(chosen)
    let loaded = try store.load()
    try #require(loaded == chosen, "saved log settings did not read back")
    let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
    try #require(mode?.intValue == 0o600, "the settings file is not private")
    try #require(
        chosen.engineEnvironment == [
            "COPYTRADING_DESKTOP_DIAGNOSTICS_RETENTION_DAYS": "30",
            "COPYTRADING_DESKTOP_DIAGNOSTICS_MAX_BYTES": String(512 * 1_024 * 1_024),
        ],
        "the engine did not receive the chosen retention and limit"
    )
    try verifyThrows(
        { _ = try DiagnosticsSettings(ageDays: 0, storageLimitBytes: 256 * 1_024 * 1_024) },
        matching: { $0 as? DiagnosticsSettingsError == .invalid },
        "zero retention days must be rejected"
    )
    try verifyThrows(
        { _ = try DiagnosticsSettings(ageDays: 7, storageLimitBytes: 123) },
        matching: { $0 as? DiagnosticsSettingsError == .invalid },
        "an unsupported storage limit must be rejected"
    )
    try Data(#"{"ageDays": 9999, "storageLimitBytes": 1}"#.utf8).write(to: store.url)
    try verifyThrows(
        { _ = try store.load() },
        matching: { $0 as? DiagnosticsSettingsError == .invalid },
        "a tampered settings file must not load"
    )
}

private func line(_ kind: String, at: String, _ fields: String) -> String {
    #"{"kind":"\#(kind)","at":"\#(at)",\#(fields)}"#
}

private func journalReadsNewestFirstAcrossRotations(_ root: URL) throws {
    let directory = root.appending(path: "rotations", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let oldest = line(
        "trading", at: "2026-09-30T10:00:00.000+00:00",
        #""operation":"model.parse","outcome":"returned","created_at_ns":1"#)
    let middle = line(
        "trading", at: "2026-09-30T10:00:01.000+00:00",
        #""operation":"execution.risk_checks","outcome":"raised","created_at_ns":2"#)
    let newest = line(
        "stage", at: "2026-09-30T10:00:02.500+00:00",
        #""stage":"completed","outcome":"completed","command_id":"sim-1","payload":null,"created_at_ns":3"#)
    try Data((oldest + "\n").utf8).write(to: directory.appending(path: "diagnostics.jsonl.1"))
    try Data((middle + "\n" + newest + "\n").utf8).write(to: directory.appending(path: "diagnostics.jsonl"))

    let journal = DiagnosticsJournal(directory: directory)
    let entries = try journal.entries()
    try #require(
        entries.map(\.name) == ["completed", "execution.risk_checks", "model.parse"],
        "journal entries must read newest first across rotations")
    try #require(entries[0].kind == .stage && entries[0].outcome == "completed", "stage record was misread")
    try #require(
        entries[0].fields.contains { $0.name == "command_id" && $0.value == "sim-1" },
        "stage fields were not kept for the reader")
    try #require(
        !entries[0].fields.contains { $0.name == "payload" || $0.name == "created_at_ns" },
        "the payload and raw clock belong outside the field list")
    let expected = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-09-30T10:00:02.500Z")
    try #require(entries[0].at == expected, "journal time was misread")
    try #require(Set(entries.map(\.id)).count == 3, "journal entries need distinct identities")
    let reread = try journal.entries()
    try #require(reread.map(\.id) == entries.map(\.id), "entry identities must survive a reread")
    let limited = try journal.entries(limit: 2)
    try #require(limited.count == 2, "the read limit was ignored")
    try #require(journal.usageBytes() > 0, "journal size was not measured")
    let exported = try journal.exportText()
    try #require(exported.hasPrefix(oldest), "the export must run oldest first")
}

private func journalSkipsDamagedLinesAndReadsPayloads(_ root: URL) throws {
    let directory = root.appending(path: "payloads", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let payload = line(
        "payload", at: "2026-09-30T11:00:00.000+00:00",
        #""capture_kind":"model_response","capture_status":"complete","trace_id":"abc","payload":{"reply":"ignore [REDACTED]"},"created_at_ns":4"#
    )
    let text = ["{not json", payload, #"{"kind":"unknown","at":"2026-09-30T11:00:00.000+00:00"}"#, ""].joined(separator: "\n")
    try Data(text.utf8).write(to: directory.appending(path: "diagnostics.jsonl"))

    let entries = try DiagnosticsJournal(directory: directory).entries()
    try #require(entries.count == 1, "damaged or unknown lines must be skipped, not fail the read")
    try #require(entries[0].kind == .payload && entries[0].name == "model_response", "payload record was misread")
    try #require(entries[0].traceID == "abc", "the trace identity was lost")
    try #require(entries[0].payloadJSON?.contains("ignore [REDACTED]") == true, "the payload was not shown")
    try #require(entries[0].searchText.contains("ignore [redacted]"), "search must cover the payload")
    let absent = try DiagnosticsJournal(directory: root.appending(path: "absent")).entries()
    try #require(absent.isEmpty, "a journal that does not exist yet reads as empty")
}
