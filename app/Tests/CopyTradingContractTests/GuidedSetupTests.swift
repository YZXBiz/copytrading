import DesktopCore
import Foundation

@MainActor
func runGuidedSetupTests() throws {
    try progressTicksFromTheDraft()
    try savedKeysCountTowardProgress()
    try helpArticlesAreCompleteAndLinked()
    try newAccountsAndGurusStartUsable()
    try unsavedChangesFollowTheSavedSetup()
    print("CopyTradingContractTests: the guide's checklist, help articles, and setup edits follow the draft")
}

@MainActor
private func progressTicksFromTheDraft() throws {
    var draft = ConnectionsDraft()
    func progress() -> SetupProgress {
        SetupProgress(
            draft: draft, hasSavedKeys: false, hasSavedProviderKey: false, savedKeyAccountIDs: [], isSetUp: false)
    }
    try verifyGuide(progress().completed == 0, "An empty draft ticked a step")
    try verifyGuide(progress().next == .discord, "An empty draft did not start at Discord")

    draft.channels = "123"
    try verifyGuide(!progress().isDone(.discord), "A channel without a token ticked Discord")
    draft.discordToken = "typed"
    try verifyGuide(progress().isDone(.discord), "A channel and a token did not tick Discord")

    draft.modelName = "claude-sonnet-5-5"
    try verifyGuide(!progress().isDone(.interpreter), "A model without a key ticked the interpreter")
    draft.providerAPIKey = "typed"
    try verifyGuide(progress().isDone(.interpreter), "A model and a key did not tick the interpreter")

    draft.accounts = [TradingAccountDraft(name: "primary")]
    try verifyGuide(!progress().isDone(.account), "An account without keys ticked the broker step")
    draft.accounts[0].key = "key"
    draft.accounts[0].secret = "secret"
    try verifyGuide(progress().isDone(.account), "An account with keys did not tick the broker step")

    var route = TradingRouteDraft()
    draft.routes = [route]
    try verifyGuide(!progress().isDone(.guru), "An unnamed guru with no account ticked the guru step")
    route.displayName = "Alex"
    route.connections = [TradingConnectionDraft(accountID: "primary")]
    draft.routes = [route]
    try verifyGuide(progress().isDone(.guru), "A named guru copying into an account did not tick the guru step")
    try verifyGuide(progress().isReadyToCheck, "Four finished steps did not allow a check")
    try verifyGuide(!progress().isDone(.start), "An unsaved setup ticked Start")
    try verifyGuide(progress().next == .start, "The last step was not next")

    draft.routes[0].connections = [TradingConnectionDraft(accountID: "removed-account")]
    try verifyGuide(!progress().isDone(.guru), "A guru copying into a missing account ticked the guru step")
}

@MainActor
private func savedKeysCountTowardProgress() throws {
    var draft = ConnectionsDraft()
    draft.channels = "123"
    draft.modelName = "deepseek-flash"
    draft.accounts = [TradingAccountDraft(name: "paper")]
    let saved = SetupProgress(
        draft: draft, hasSavedKeys: true, hasSavedProviderKey: true, savedKeyAccountIDs: ["paper"], isSetUp: true)
    try verifyGuide(
        saved.isDone(.discord) && saved.isDone(.interpreter) && saved.isDone(.account) && saved.isDone(.start),
        "Keys saved in the Keychain did not count as entered")
    try verifyGuide(saved.fraction > 0.7 && saved.fraction < 1, "Progress did not count four of five steps")
}

@MainActor
private func helpArticlesAreCompleteAndLinked() throws {
    try verifyGuide(Set(SetupHelp.all.map(\.id)).count == SetupHelp.all.count, "Two help articles share an ID")
    for article in SetupHelp.all {
        try verifyGuide(!article.title.isEmpty && article.steps.count >= 2, "\(article.id) has too few steps")
        try verifyGuide(
            article.steps.allSatisfy { !$0.contains("snake_case") && !$0.isEmpty }, "\(article.id) has an empty step")
        if let destination = article.destination {
            try verifyGuide(destination.url.scheme == "https", "\(article.id) links somewhere other than https")
        }
    }
    try verifyGuide(SetupHelp.discordToken.caution != nil, "The Discord token article lost its warning")
    try verifyGuide(
        TradingProviderName.allCases.allSatisfy { SetupHelp.interpreterKey(for: $0).destination != nil },
        "An interpreter provider has no key article")
    try verifyGuide(
        SetupHelp.prefilledModel(for: .deepseek) == "deepseek-flash"
            && SetupHelp.prefilledModel(for: .openAICompatible) == nil,
        "The Model field did not start with the provider's recommended model")
    try verifyGuide(
        Reason.text("provider_model_not_found") == "The model service has no model by that name",
        "A missing model reached Activity as an engine code")
}

@MainActor
private func newAccountsAndGurusStartUsable() throws {
    var draft = ConnectionsDraft()
    try verifyGuide(draft.isEmpty && draft.accounts.isEmpty && draft.routes.isEmpty, "A new draft is not empty")
    try verifyGuide(draft.nextAccountName == "primary", "The first account is not called primary")
    draft.accounts = [TradingAccountDraft(name: "primary")]
    try verifyGuide(draft.nextAccountName == "account-2", "The second account name is not account-2")

    let first = TradingRouteDraft()
    let second = TradingRouteDraft()
    try verifyGuide(first.guruID != second.guruID, "Two new gurus share an ID")
    try verifyGuide(
        first.guruID.range(of: "^guru-[a-f0-9]{8}$", options: .regularExpression) != nil,
        "A generated guru ID does not satisfy the profile rules")

    let model = AppModel()
    model.addGuru()
    try verifyGuide(model.setupDraft.routes.count == 1 && model.setupEditor != nil, "Add Guru did not open the new guru")
    try verifyGuide(model.setupDraft.routes[0].connections.isEmpty, "A guru copied into an account that does not exist")
    model.addAccount()
    try verifyGuide(
        model.setupDraft.routes[0].connections.map(\.accountID) == ["primary"],
        "The first account was not attached to the guru waiting for one")
    model.setupDraft.accounts[0].name = "main"
    model.renameAccountReferences(from: "primary", to: "main")
    try verifyGuide(
        model.setupDraft.routes[0].connections.map(\.accountID) == ["main"], "Renaming an account lost the guru's link to it")
}

@MainActor
private func unsavedChangesFollowTheSavedSetup() throws {
    let model = AppModel()
    try verifyGuide(!model.hasUnsavedSetupChanges, "An untouched first run counted as unsaved")
    model.setupDraft.channels = "123"
    try verifyGuide(model.hasUnsavedSetupChanges && model.showsSetupChangesBar, "A first edit did not show the changes bar")

    let profile = try TradingProfileBuilder().build(
        TradingProfileDraft(guruID: "alex", displayName: "Alex", prefix: "ALERT:", exitBasis: .originalPosition))
    let saved = TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["123"]),
        provider: TradingProviderConfiguration(name: .anthropic, model: "claude-sonnet-5-5"),
        accounts: [TradingAccountConfiguration(id: "paper", environment: .paper)],
        profiles: [profile],
        routes: [
            TradingRouteConfiguration(
                channelID: "123", authorID: nil, guruID: "alex", profileRevision: profile.profileRevision,
                connections: [TradingRouteConnection(accountID: "paper", mode: .fixed, amountUSD: "500", defaultFraction: nil)])
        ]
    )
    model.savedTradingConfiguration = saved
    model.hasTradingSecrets = true
    model.setupDraftSource = nil
    model.syncSetupDraftWithSaved()
    try verifyGuide(!model.hasUnsavedSetupChanges, "A draft refilled from the saved setup counted as unsaved")
    try verifyGuide(model.setupProgress.isComplete, "A saved setup did not complete the guide")

    model.setupDraft.routes[0].displayName = "Alex Chen"
    try verifyGuide(model.hasUnsavedSetupChanges, "Renaming a saved guru did not count as unsaved")
    model.discardSetupChanges()
    try verifyGuide(
        !model.hasUnsavedSetupChanges && model.setupDraft.routes[0].displayName == "Alex",
        "Discard Changes did not return to the saved setup")
}

private func verifyGuide(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw NSError(domain: "GuidedSetupTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
