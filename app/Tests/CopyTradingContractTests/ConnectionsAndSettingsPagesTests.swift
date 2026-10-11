import DesktopCore
import Foundation
import Testing

@MainActor
func runConnectionsAndSettingsPagesTests() throws {
    try connectionTilesFollowTheDraft()
    try settingsRetracesPagesAndClosesBack()
    print("CopyTradingContractTests: Connections tiles follow the draft; Settings goes back through its pages and closes")
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
