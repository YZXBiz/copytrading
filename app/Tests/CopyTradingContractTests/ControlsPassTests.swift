import AppLocalizationCore
import DesktopCore
import Foundation
import Testing

/// Controls the 2026-10-15 pass found doing something other than what they say.
@MainActor
func runControlsPassTests() async throws {
    try backAndForwardRetraceOnlyTheOwnersMoves()
    try await aConnectionCheckThatCannotRunFailsInWords()
    try connectWithNothingEnteredSaysWhatItNeeds()
    try pickingTheStartingServiceStillSuggestsItsModel()
    try await alertsAreNotDoneWhileTheirCheckFails()
    try anAccountNameTheEngineRefusesIsFlagged()
    try guideStopsOpenSomewhereEvenBeforeSetup()
    try guideShortcutsNameOnlyScreensThatExist()
    try showTipsAgainSaysWhenTheyReturn()
    try examplesSayBuyOrSell()
    try await accountButtonsWithNoEngineSaySo()
    try selfTestWaitsForARunningEngine()
    try assistantSuggestionsBeforeSetupAreAboutSettingUp()
    print("CopyTradingContractTests: every control the controls pass fixed does what it says")
}

@MainActor
private func backAndForwardRetraceOnlyTheOwnersMoves() throws {
    let model = AppModel()
    model.savedTradingConfiguration = try controlsConfiguration(guru: "zhao")
    model.selectedScreen = .connections
    model.screenHistory = ScreenHistory()  // what a launch does after choosing its first screen
    try #require(model.screenHistory.back.isEmpty, "Back had somewhere to go on a fresh window")

    model.selectedScreen = .guru("zhao")
    model.selectedScreen = .account("primary")
    model.goBack()
    try #require(model.selectedScreen == .guru("zhao"), "Back did not return to the guru")
    try #require(model.screenHistory.forward == [.account("primary")], "Back did not keep the account for Forward")
    model.goForward()
    try #require(model.selectedScreen == .account("primary"), "Forward did not return to the account")
    try #require(model.screenHistory.back == [.connections, .guru("zhao")], "Forward recorded itself as a new visit")

    // A guru removed since is passed over.
    model.savedTradingConfiguration = try controlsConfiguration(guru: nil)
    model.goBack()
    try #require(model.selectedScreen == .connections, "Back stopped on a guru that no longer exists")
}

@MainActor
private func aConnectionCheckThatCannotRunFailsInWords() async throws {
    let model = AppModel()
    model.isTradingUnlocked = true
    model.setupDraft.channels = "123456789012345678"
    model.setupDraft.discordToken = "typed"
    let check = await model.checkConnection(.discord)
    try #require(check?.state == .failed, "A check with no engine to run it passed silently")
    try #require(
        ConnectionProblem.text(for: try #require(check)).contains("Settings → Engine"),
        "The failed check did not say how to get the engine back")
    try #require(!model.setupProgress.isDone(.discord), "A check that couldn't run ticked the Discord step")
}

@MainActor
private func connectWithNothingEnteredSaysWhatItNeeds() throws {
    var draft = ConnectionsDraft()
    try #require(
        draft.missingToConnect(.discord, savedSecret: false) == "Enter a channel ID and your Discord token to connect.",
        "An empty Discord panel closed without a word")
    try #require(draft.missingToConnect(.discord, savedSecret: true) == nil, "A saved token still counted as nothing entered")
    draft.channels = "123"
    try #require(draft.missingToConnect(.discord, savedSecret: false) == nil, "A channel alone could not be kept for later")
    draft.modelName = " "
    try #require(
        draft.missingToConnect(.interpreter, savedSecret: false) == "Enter the model's name to connect.",
        "An interpreter with no model closed without a word")
    try #require(
        draft.missingToConnect(.alerts, savedSecret: false) == draft.missingForAlerts(savedSecret: false),
        "Alerts lost their own message")
}

@MainActor
private func pickingTheStartingServiceStillSuggestsItsModel() throws {
    var draft = ConnectionsDraft()
    try #require(draft.provider == .anthropic && draft.modelName.isEmpty, "The draft no longer starts on Anthropic with no model")
    draft.pick(.anthropic)
    try #require(draft.modelName == SetupHelp.suggestedModel(for: .anthropic), "Anthropic opened with an empty Model field")
    draft.modelName = "my-own-model"
    draft.pick(.anthropic)
    try #require(draft.modelName == "my-own-model", "Picking the same service again replaced a typed model")
}

@MainActor
private func alertsAreNotDoneWhileTheirCheckFails() async throws {
    let model = AppModel()
    model.isTradingUnlocked = true
    model.setupDraft.notificationService = .discord
    model.setupDraft.notificationsEnabled = true
    model.setupDraft.notificationToken = "https://discord.com/api/webhooks/1/abc"
    try #require(model.alertsReady, "Alerts that were never checked did not read as set up")
    _ = await model.checkConnection(.alerts)
    try #require(!model.alertsReady, "The alerts step read as done while its check failed")
    model.setupDraft.notificationToken = "https://discord.com/api/webhooks/2/def"
    try #require(model.alertsReady, "An edited webhook kept the old failure")
}

@MainActor
private func anAccountNameTheEngineRefusesIsFlagged() throws {
    let model = AppModel()
    var account = TradingAccountDraft(name: "my acct!")
    account.key = "key"
    account.secret = "secret"
    try #require(account.nameProblem != nil, "A name with spaces was accepted")
    model.setupDraft.accounts = [account]
    try #require(!model.setupProgress.isDone(.account), "An account the engine would refuse ticked the step")
    try #require(
        ConnectionStatus.account(account, in: model).text == "Needs a valid name", "The account row did not flag its name")
    model.setupDraft.accounts[0].name = "paper-main_2"
    try #require(model.setupDraft.accounts[0].nameProblem == nil, "A valid name was flagged")
    try #require(model.setupProgress.isDone(.account), "A valid account with keys did not tick the step")
    try #require(TradingAccountDraft(name: " ").nameProblem == "Give the account a name.", "A blank name was not asked for")
}

@MainActor
private func guideStopsOpenSomewhereEvenBeforeSetup() throws {
    for stop in GuideJourneyStop.all {
        let before = stop.place(firstAccount: nil)
        try #require(before.screen != .gettingStarted, "\(stop.title) went nowhere before setup")
        let after = stop.place(firstAccount: "primary")
        if stop.screen == nil {
            try #require(before.screen == .connections && before.title == "Connections", "\(stop.title) before setup")
            try #require(after.screen == .account("primary") && after.title == "Your account", "\(stop.title) after setup")
        }
    }
}

@MainActor
private func guideShortcutsNameOnlyScreensThatExist() throws {
    for shortcut in GuideShortcut.all {
        for gone in ["Today", "People", "Activity,", "posts in Activity"] {
            try #require(!shortcut.action.contains(gone), "The guide still promises \"\(shortcut.action)\"")
        }
    }
    let keys = GuideShortcut.all.map { $0.keys.joined() }
    for expected in ["⌘K", "⌘J", "⌘1–9", "⌘[⌘]", "⌘R", "⌘,"] {
        try #require(keys.contains(expected), "The guide doesn't list \(expected)")
    }
}

@MainActor
private func showTipsAgainSaysWhenTheyReturn() throws {
    let model = AppModel()
    model.showTipsAgain()
    try #require(model.message?.contains("once copying is set up") == true, "Show Tips Again said nothing before setup")
}

@MainActor
private func examplesSayBuyOrSell() throws {
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    preference.select(.english)
    try #require(
        TradingInstructionAction.allCases.map(\.title) == ["Buy", "Sell part", "Sell all"],
        "Example actions read \(TradingInstructionAction.allCases.map(\.title))")
}

@MainActor
private func accountButtonsWithNoEngineSaySo() async throws {
    let feature = AccountFeatureModel()
    feature.authorizePrivateEvidence()
    await feature.control(accountID: "primary", action: .pause, using: nil)
    try #require(
        feature.errors["primary"] == AccountFeatureModel.noEngine, "Stop Copying with no engine did nothing and said nothing")
}

@MainActor
private func selfTestWaitsForARunningEngine() throws {
    let model = AppModel()
    for (state, runs) in [(AppModel.RuntimeState.stopped, false), (.starting, false), (.failed, false), (.ready, true), (.degraded, true)] {
        model.runtimeState = state
        try #require(model.isEngineRunning == runs, "Run Self-Test was \(runs ? "off" : "on") with the engine \(state)")
    }
}

@MainActor
private func assistantSuggestionsBeforeSetupAreAboutSettingUp() throws {
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    preference.select(.english)
    for screen in AppModel.Screen.pages {
        let suggestions = AssistantSuggestions.suggestions(for: screen, guru: nil, isSetUp: false)
        try #require(suggestions.count == 4 && Set(suggestions).count == 4, "\(screen) did not offer four setup questions")
        for nothingYet in ["guru", "post", "What's in my"] {
            try #require(
                !suggestions.contains { $0.contains(nothingYet) }, "Before setup the assistant offered \(suggestions)")
        }
    }
}

private func controlsConfiguration(guru: String?) throws -> TradingConfiguration {
    let profiles = try guru.map { [try TradingProfileBuilder().build(TradingProfileDraft(guruID: $0, displayName: $0.capitalized))] } ?? []
    return TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["123"]),
        provider: TradingProviderConfiguration(name: .deepseek, model: "deepseek-flash"),
        accounts: [TradingAccountConfiguration(id: "primary", environment: .paper, policy: TradingAccountPolicy())],
        profiles: profiles,
        routes: profiles.map {
            TradingRouteConfiguration(
                channelID: "123", authorID: nil, guruID: $0.guruID, profileRevision: $0.profileRevision,
                connections: [TradingRouteConnection(accountID: "primary", fullPositionUSD: "600")])
        })
}
