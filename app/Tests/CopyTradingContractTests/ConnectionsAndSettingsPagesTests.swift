import DesktopCore
import Foundation
import Testing

@MainActor
func runConnectionsAndSettingsPagesTests() throws {
    try connectionTilesFollowTheDraft()
    try settingsRetracesPagesAndClosesBack()
    try diagnosticsRecordsReadInWords()
    print("CopyTradingContractTests: Connections tiles follow the draft; Settings goes back through its pages and closes")
}

/// Every ledger event the engine journals (`safe_ledger_event`) and every self-test stage has its
/// own title in both languages; none falls back to its code, and a Discord post names no provider.
@MainActor
private func diagnosticsRecordsReadInWords() throws {
    let ledgerEvents = [
        "account_bound", "signal_rejected", "message", "skipped", "message_done", "order_prepared", "submit_started",
        "submission_aborted", "submission_uncertain", "broker_acknowledged", "cancel_requested", "quote_unavailable",
        "submit_error", "submission_quote", "manual_sale_recorded", "order_intent_released",
        "late_order_incident_cleared", "order_update", "late_order_incident_opened", "late_order_incident_reopened",
    ]
    try #require(
        Set(ledgerEvents) == Set(DiagnosticsJournalEntry.ledgerTitles.keys),
        "ledger titles cover \(DiagnosticsJournalEntry.ledgerTitles.keys.sorted())")
    try #require(
        Set(["captured", "parsed", "completed", "failed"]) == Set(DiagnosticsJournalEntry.stageTitles.keys),
        "self-test titles cover \(DiagnosticsJournalEntry.stageTitles.keys.sorted())")
    let longest = DiagnosticsJournalEntry.ledgerTitles.values.map(\.count).max() ?? 0
    try #require(longest <= 22, "a ledger title is \(longest) characters, too long for the list")

    func entry(_ line: String) throws -> DiagnosticsJournalEntry {
        let directory = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data((line + "\n").utf8).write(to: directory.appending(path: DiagnosticsJournal.fileName))
        return try #require(try DiagnosticsJournal(directory: directory).entries().first)
    }
    let post = try entry(
        #"{"kind":"payload","at":"2026-10-15T20:00:00.000+00:00","capture_kind":"source_event","capture_status":"complete","provider":"other","created_at_ns":1}"#
    )
    try #require(!post.displayFields.contains { $0.label == "Provider" }, "a Discord post named provider \(post.displayFields)")
    let stage = try entry(
        #"{"kind":"stage","at":"2026-10-15T20:00:01.000+00:00","stage":"parsed","outcome":"parsed","created_at_ns":2}"#
    )
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    preference.select(.simplifiedChinese)
    try #require(
        stage.title == "自检：已读取" && stage.outcomeTitle == "已读取",
        "a self-test stage read \(stage.title) · \(stage.outcomeTitle) in 简体中文")
}

@MainActor
private func connectionTilesFollowTheDraft() throws {
    let model = AppModel()
    for kind in ConnectionKind.allCases {
        try #require(ConnectionSummary.of(kind, in: model) == nil, "An empty draft showed a \(kind) tile")
    }

    model.setupDraft.channels = "123, 456"
    let discord = ConnectionSummary.of(.discord, in: model)
    try #require(discord?.detail == "2 channels, anyone who posts", "Discord read \(discord?.detail ?? "nothing")")
    try #require(discord?.status.text == "Needs a token", "A channel without a token did not ask for one")
    model.setupDraft.authors = "789"
    model.setupDraft.discordToken = "typed"
    let named = ConnectionSummary.of(.discord, in: model)
    try #require(named?.detail == "2 channels, 1 author", "Allowed authors did not show: \(named?.detail ?? "nothing")")
    try #require(named?.status.text == "Not saved yet", "A typed token did not read as unsaved")

    model.setupDraft.provider = .deepseek
    model.setupDraft.modelName = " deepseek-flash "
    let interpreter = ConnectionSummary.of(.interpreter, in: model)
    try #require(interpreter?.title == "DeepSeek", "The interpreter tile did not name its provider")
    try #require(interpreter?.detail == "deepseek-flash", "The interpreter tile did not show its trimmed model")
    try #require(interpreter?.status.text == "Needs an API key", "A model without a key did not ask for one")
    model.hasTradingSecrets = true
    try #require(
        ConnectionSummary.of(.interpreter, in: model)?.status.text == "Needs an API key",
        "A key saved with no setup for this provider counted as this provider's key")
    model.setupDraft.providerAPIKey = "typed"
    try #require(
        ConnectionSummary.of(.interpreter, in: model)?.status.text == "Not saved yet", "A typed key still asked for one")
    model.setupDraft.providerAPIKey = ""
    model.setupDraft.provider = .ollama
    try #require(
        ConnectionSummary.of(.interpreter, in: model)?.status.text == "Not saved yet", "A local model asked for a key")
    model.setupDraft.provider = .deepseek

    model.setupDraft.notificationChatID = "42"
    try #require(ConnectionSummary.of(.alerts, in: model) == nil, "Alerts showed a tile while turned off")
    model.setupDraft.notificationsEnabled = true
    try #require(ConnectionSummary.of(.alerts, in: model)?.detail == "Chat 42", "The alerts tile did not show its chat")
}

@MainActor
private func settingsRetracesPagesAndClosesBack() throws {
    let model = AppModel()
    model.screenBeforeSettings = .account("primary")
    model.selectedScreen = .settings
    model.show(.general)
    try #require(model.settingsTrail.isEmpty, "Opening the page already shown added a step back")
    model.show(.engine)
    model.show(.logs)
    try #require(model.settingsTrail == [.general, .engine], "The trail was \(model.settingsTrail)")
    model.settingsBack()
    try #require(model.settingsPage == .engine, "Back did not return to Engine")
    model.closeSettings()
    try #require(model.selectedScreen == .account("primary"), "Closing Settings did not return to the account")
    try #require(model.settingsTrail.isEmpty, "Closing Settings kept the trail")

    model.screenBeforeSettings = .settings
    model.selectedScreen = .settings
    model.closeSettings()
    try #require(model.selectedScreen == model.homeScreen, "Closing Settings with nowhere to return did not land at home")
}
