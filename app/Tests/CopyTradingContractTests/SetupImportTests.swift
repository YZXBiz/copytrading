import DesktopCore
import Foundation
import Testing

/// Import Setup reads a key file the owner chose into the setup's fields, and never lets a file
/// give keys to a live account or show a value back.
@MainActor
func runSetupImportTests() throws {
    try theOwnersKeyFileFillsEverySetupStep()
    try aValueOnTheLabelsLineIsRead()
    try anAnthropicKeyAloneChoosesAnthropic()
    try aLiveAccountNeverGetsImportedKeys()
    try aGuruLineAddsAGuruCopyingIntoThePaperAccount()
    try aFileWithNothingRecognisableIsEmpty()
    try fieldsTheFileDoesNotNameKeepTheirValues()
    try theSummaryNeverShowsAValue()
}

/// The layout of the owner's own key file, with made-up values.
private let ownersKeyFile = """
    CopyTrading test keys (paper only). Delete this file after you're done.

    Discord token:
    fake-discord-token-value

    Discord channel ID:
    1234567890123456789

    Model service: DeepSeek, model deepseek-flash
    DeepSeek API key:
    fake-deepseek-key-value

    Alpaca PAPER API key:
    fake-alpaca-key-value

    Alpaca PAPER API secret:
    fake-alpaca-secret-value
    """

private let fakeValues = [
    "fake-discord-token-value", "1234567890123456789", "fake-deepseek-key-value", "fake-alpaca-key-value",
    "fake-alpaca-secret-value", "fake-anthropic-key-value",
]

@MainActor
private func theOwnersKeyFileFillsEverySetupStep() throws {
    let imported = SetupImport(text: ownersKeyFile)
    var draft = ConnectionsDraft()
    imported.apply(to: &draft)

    try #require(draft.channels == "1234567890123456789", "the channel was not filled")
    try #require(draft.discordToken == "fake-discord-token-value", "the Discord token was not filled")
    try #require(draft.provider == .deepseek, "the model service line did not choose DeepSeek")
    try #require(draft.modelName == "deepseek-flash", "the model on the service line was not used")
    try #require(draft.providerAPIKey == "fake-deepseek-key-value", "the DeepSeek key was not filled")
    try #require(draft.accounts.count == 1, "the Alpaca keys did not make one account")
    let account = draft.accounts[0]
    try #require(account.name == "primary" && account.environment == .paper, "the new account is not paper “primary”")
    try #require(account.key == "fake-alpaca-key-value", "the Alpaca key was not filled")
    try #require(account.secret == "fake-alpaca-secret-value", "the Alpaca secret was not filled")
    try #require(!imported.isEmpty, "a full key file read as empty")
}

@MainActor
private func aValueOnTheLabelsLineIsRead() throws {
    let imported = SetupImport(
        text: """
            Discord token: fake-discord-token-value
            Discord channel ID: 1234567890123456789
            DeepSeek API key: fake-deepseek-key-value
            Alpaca key: fake-alpaca-key-value
            Alpaca secret: fake-alpaca-secret-value
            """)
    var draft = ConnectionsDraft()
    imported.apply(to: &draft)

    try #require(draft.discordToken == "fake-discord-token-value", "a same-line token was not read")
    try #require(draft.channels == "1234567890123456789", "a same-line channel was not read")
    try #require(draft.provider == .deepseek && draft.providerAPIKey == "fake-deepseek-key-value", "a same-line key was not read")
    try #require(
        draft.accounts.first?.key == "fake-alpaca-key-value" && draft.accounts.first?.secret == "fake-alpaca-secret-value",
        "same-line Alpaca keys were not read")
}

@MainActor
private func anAnthropicKeyAloneChoosesAnthropic() throws {
    var draft = ConnectionsDraft()
    draft.provider = .deepseek
    draft.modelName = "deepseek-flash"
    SetupImport(text: "Anthropic-key:\nfake-anthropic-key-value").apply(to: &draft)

    try #require(draft.provider == .anthropic, "a lone Anthropic key did not choose Anthropic")
    try #require(draft.providerAPIKey == "fake-anthropic-key-value", "the Anthropic key was not filled")
    try #require(
        draft.modelName == (SetupHelp.prefilledModel(for: .anthropic) ?? ""),
        "Anthropic did not get its prefilled model, got \(draft.modelName)")
}

@MainActor
private func aLiveAccountNeverGetsImportedKeys() throws {
    var draft = ConnectionsDraft()
    draft.accounts = [TradingAccountDraft(name: "primary", environment: .live)]
    SetupImport(text: ownersKeyFile).apply(to: &draft)

    try #require(draft.accounts.count == 2, "the keys did not go to a new paper account")
    let live = draft.accounts[0]
    try #require(live.environment == .live && live.key.isEmpty && live.secret.isEmpty, "a live account was given imported keys")
    let paper = draft.accounts[1]
    try #require(paper.environment == .paper, "the new account is not paper")
    try #require(paper.name != live.name, "the new paper account reused the live account's name")
    try #require(paper.key == "fake-alpaca-key-value" && paper.secret == "fake-alpaca-secret-value", "the paper account lacks the keys")
}

@MainActor
private func aGuruLineAddsAGuruCopyingIntoThePaperAccount() throws {
    var draft = ConnectionsDraft()
    SetupImport(text: ownersKeyFile + "\n\nGuru:\nZhao").apply(to: &draft)

    try #require(draft.routes.count == 1, "the guru line did not add one guru")
    let route = draft.routes[0]
    try #require(route.displayName == "Zhao", "the guru is not named from the file")
    try #require(route.connection?.accountID == "primary", "the guru does not copy into the paper account")
    try #require(draft.effectiveChannel(for: route) == "1234567890123456789", "the guru is not on the imported channel")
}

@MainActor
private func aFileWithNothingRecognisableIsEmpty() throws {
    let imported = SetupImport(text: "Shopping list:\nmilk\n\nNotes: call the bank\nhello world")
    try #require(imported.isEmpty, "a file with no setup in it read as a setup")
    try #require(SetupImport(text: "").isEmpty, "an empty file read as a setup")
}

@MainActor
private func fieldsTheFileDoesNotNameKeepTheirValues() throws {
    var draft = ConnectionsDraft()
    draft.channels = "999999999999999999"
    draft.authors = "111111111111111111"
    draft.provider = .openai
    draft.modelName = "my-model"
    draft.providerAPIKey = "typed-openai-key"
    SetupImport(text: "Discord token:\nfake-discord-token-value").apply(to: &draft)

    try #require(draft.discordToken == "fake-discord-token-value", "the named token was not filled")
    try #require(draft.channels == "999999999999999999", "an unnamed channel was overwritten")
    try #require(draft.authors == "111111111111111111", "unnamed authors were overwritten")
    try #require(
        draft.provider == .openai && draft.modelName == "my-model" && draft.providerAPIKey == "typed-openai-key",
        "an unnamed model service was overwritten")
    try #require(draft.accounts.isEmpty && draft.routes.isEmpty, "a file without Alpaca keys or a guru added one")
}

@MainActor
private func theSummaryNeverShowsAValue() throws {
    let full = SetupImport(text: ownersKeyFile + "\n\nAnthropic-key:\nfake-anthropic-key-value")
    let partial = SetupImport(text: "Discord token:\nfake-discord-token-value\nAlpaca key: fake-alpaca-key-value")
    for imported in [full, partial] {
        let lines = imported.filled + imported.missing
        try #require(!imported.filled.isEmpty, "the summary lists nothing filled")
        for line in lines {
            for value in fakeValues {
                try #require(!line.contains(value), "the summary shows a value: \(line)")
            }
        }
    }
    try #require(!partial.missing.isEmpty, "a partial file lists nothing missing")
}
