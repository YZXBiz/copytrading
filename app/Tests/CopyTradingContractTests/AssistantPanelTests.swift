import CopyTradingTestSupport
import DesktopCore
import Foundation

@MainActor
func runAssistantPanelTests() throws {
    try suggestionsLeadWithTheScreen()
    try theContextNamesWhatIsSelected()
    try theContextNamesTheGurusAndTheOneThatIsOpen()
    try linksOpenThePostAccountOrGuru()
    try inSimplifiedChineseTheAssistantAsksAndShowsItsWorkInChinese()
    try headingsNeedASpaceSoTickerTagsStayAsWritten()
    print(
        "CopyTradingContractTests: the assistant suggests by screen, sends what is selected and the app's language, "
            + "opens what it links to, and shows the engine's lines in 简体中文")
}

private struct AssistantPanelFailure: Error, CustomStringConvertible {
    let description: String
}

private func verifyPanel(_ condition: Bool, _ message: String) throws {
    guard condition else { throw AssistantPanelFailure(description: message) }
}

@MainActor
private func suggestionsLeadWithTheScreen() throws {
    let screens: [AppModel.Screen] = [.account("primary"), .guru("zhao")] + AppModel.Screen.pages
    for screen in screens {
        for selected in [false, true] {
            let suggestions = AssistantSuggestions.suggestions(for: screen, guru: "Zhao", hasSelectedPost: selected, isSetUp: true)
            try verifyPanel(suggestions.count == 4, "\(screen) did not offer four suggestions")
            try verifyPanel(Set(suggestions).count == 4, "\(screen) repeated a suggestion")
        }
    }
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .account("primary"), guru: nil, hasSelectedPost: true, isSetUp: true).first
            == "Why was this post skipped?",
        "A selected post did not lead")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .guru("zhao"), guru: "Zhao", isSetUp: true).first == "How did Zhao do this week?",
        "A guru's page did not lead with the guru")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .guru("zhao"), guru: nil, isSetUp: true).first == "How did my gurus do this week?",
        "A guru's page without a name named one")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .account("primary"), guru: nil, isSetUp: true).first == "What's in my paper account?",
        "An account's page did not lead with the account")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .connections, guru: nil, isSetUp: true).first == "How do I add Telegram alerts?",
        "Connections did not lead with setting up alerts")
    try verifyPanel(
        !AssistantSuggestions.suggestions(for: .connections, guru: nil, isSetUp: true).contains("Why was this post skipped?"),
        "A screen without a selected post asked about this post")
}

@MainActor
private func theContextNamesWhatIsSelected() throws {
    let model = AppModel()
    let post = try assistantPost(sequence: 7, sourceID: "discord:calls:7")
    model.selectedScreen = .account("paper-main")
    let onAccount = model.assistantContext(selectedPost: post)
    try verifyPanel(
        onAccount
            == AssistantAskContext(
                screen: "accounts", selectedSourceID: "discord:calls:7", selectedAccountID: "paper-main", setup: model.assistantSetup),
        "The account page did not send its account and selected post: \(onAccount)")
    model.selectedScreen = .connections
    let onConnections = model.assistantContext(selectedPost: nil)
    try verifyPanel(
        onConnections == AssistantAskContext(screen: "connections", setup: model.assistantSetup),
        "Connections sent a selection that is not on screen: \(onConnections)")
    model.selectedScreen = .gettingStarted
    try verifyPanel(
        model.assistantContext(selectedPost: nil).screen == "gettingStarted", "The screen was not named as the engine expects")
}

@MainActor
private func theContextNamesTheGurusAndTheOneThatIsOpen() throws {
    let model = AppModel()
    model.setupDraft.routes = [
        TradingRouteDraft(channelID: "111", displayName: "Zhao"),
        TradingRouteDraft(channelID: "222", displayName: "Ana"),
        TradingRouteDraft(channelID: "111", displayName: "Zhao"),
        TradingRouteDraft(channelID: "333", displayName: "  "),
    ]
    let zhao = GuruIdentity.id(channelID: "111")
    let ana = GuruIdentity.id(channelID: "222")
    model.selectedScreen = .connections
    let nothingOpen = model.assistantContext(selectedPost: nil)
    try verifyPanel(
        nothingOpen.gurus == [
            AssistantGuru(id: zhao, name: "Zhao"), AssistantGuru(id: ana, name: "Ana"),
        ],
        "The setup's gurus were not named once each: \(nothingOpen.gurus)")
    try verifyPanel(nothingOpen.selectedGuruID == nil, "A page with no guru open still named one: \(nothingOpen)")

    model.selectedScreen = .guru(ana)
    let onGuru = model.assistantContext(selectedPost: nil)
    try verifyPanel(
        onGuru.selectedGuruID == ana && onGuru.screen == "people", "The guru's page did not send its guru")
    model.selectedScreen = .account("paper-main")
    try verifyPanel(
        model.assistantContext(selectedPost: nil).selectedGuruID == nil, "An account's page sent a guru that is not on screen")
}

@MainActor
private func headingsNeedASpaceSoTickerTagsStayAsWritten() throws {
    for (line, shown) in [
        ("## Summary", "**Summary**"),
        ("# Zhao this week", "**Zhao this week**"),
        ("#NVDA long at 125", "#NVDA long at 125"),
        ("####### seven", "####### seven"),
        ("- bought NVDA", "•\u{2002}bought NVDA"),
    ] {
        let rendered = AssistantMarkdown.line(line)
        try verifyPanel(rendered == shown, "\"\(line)\" rendered as \"\(rendered)\"")
    }
}

@MainActor
private func linksOpenThePostAccountOrGuru() throws {
    let model = AppModel()
    let post = try assistantPost(sequence: 7, sourceID: "discord:calls:7")
    var focused: SourceActivity.ID?
    model.follow(AssistantLink(kind: "post", id: "discord:calls:7", title: "Open the post"), activity: [post]) {
        focused = $0
    }
    let reached = post.destinations.first?.accountID
    try verifyPanel(
        focused == 7 && (reached.map { model.selectedScreen == .account($0) } ?? true),
        "A post link did not select the post on its account")

    focused = nil
    model.selectedScreen = .connections
    model.follow(AssistantLink(kind: "post", id: "discord:calls:99", title: "Open the post"), activity: [post]) {
        focused = $0
    }
    try verifyPanel(model.selectedScreen == .connections && focused == nil, "A post that is not loaded moved the window")

    model.follow(AssistantLink(kind: "account", id: "paper-main", title: "paper-main"), activity: []) { _ in }
    try verifyPanel(model.selectedScreen == .account("paper-main"), "An account link did not open the account")

    model.follow(AssistantLink(kind: "guru", id: "zhao", title: "zhao"), activity: []) { _ in }
    try verifyPanel(model.selectedScreen == .guru("zhao"), "A guru link did not open the guru")

    model.follow(AssistantLink(kind: "elsewhere", id: "x", title: "x"), activity: []) { _ in }
    try verifyPanel(model.selectedScreen == .guru("zhao"), "An unknown link moved the window")
}

@MainActor
private func inSimplifiedChineseTheAssistantAsksAndShowsItsWorkInChinese() throws {
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    let model = AppModel()
    model.selectedScreen = .guru("zhao")

    preference.select(.english)
    try verifyPanel(model.assistantContext(selectedPost: nil).language == "en", "English did not send en")

    preference.select(.simplifiedChinese)
    try verifyPanel(
        model.assistantContext(selectedPost: nil).language == "zh-Hans", "简体中文 did not send zh-Hans")
    let suggestions = AssistantSuggestions.suggestions(for: .guru("zhao"), guru: "Zhao", isSetUp: true)
    try verifyPanel(suggestions.first == "Zhao 这周表现怎么样？", "People's first suggestion was \(suggestions)")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .guru("zhao"), guru: nil, isSetUp: true).first == "我的信号源这周表现怎么样？",
        "Gurus were not called 信号源")
    for (engine, shown) in [
        ("Looked at your accounts", "已查看你的账户"),
        ("Read paper-main's history", "已读取 paper-main 的账户历史记录"),
        ("Asked you to approve paper-main's after-restart setting", "已请你批准 paper-main 的重启后设置"),
        ("Added up Zhao's calls", "已统计 Zhao 的喊单"),
        ("Couldn't stop copying into paper-main", "未能停止跟单到 paper-main"),
        ("Couldn't ask you to approve copying into paper-main", "未能发起跟单到 paper-main 的批准请求"),
        ("Couldn't find that post", "没有找到那条帖子"),
        (
            "Your model didn't answer in time. Try again, or pick another model in Connections.",
            "AI 模型没有及时回答。请重试，或在“连接”中换一个模型。"
        ),
        ("A line the app has never seen", "A line the app has never seen"),
    ] {
        let localized = AssistantEngineText.localized(engine)
        try verifyPanel(localized == shown, "\"\(engine)\" showed as \"\(localized)\"")
    }
    try verifyPanel(
        AssistantEngineText.isRefusal("Couldn't pause copying") && !AssistantEngineText.isRefusal("Paused copying"),
        "A refused step was not told apart from one that ran")
    for (state, shown) in [("outcome_unknown", "结果未知"), ("discarded", "已作废"), ("failed", "失败")] {
        let localized = L10n.string(Humanize.code(state))
        try verifyPanel(localized == shown, "A proposal that is \(state) read \"\(localized)\"")
    }
    try verifyPanel(
        L10n.string("Approve: %@", "Resume paper-main") == "批准：Resume paper-main", "The Touch ID prompt was not in Chinese")
}

private func assistantPost(sequence: Int, sourceID: String) throws -> SourceActivity {
    try SourceActivityBuilder()
        .sequence(sequence, sourceID: sourceID).text("AMD long").posted(at: "2026-10-01T12:00:00Z").decision(nil)
        .build()
}
