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
    for screen in AppModel.Screen.allCases {
        let suggestions = AssistantSuggestions.suggestions(for: screen, guru: "Zhao")
        try verifyPanel(suggestions.count == 4, "\(screen) did not offer four suggestions")
        try verifyPanel(Set(suggestions).count == 4, "\(screen) repeated a suggestion")
    }
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .activity, guru: nil).first == "Why was this post skipped?",
        "Activity did not lead with the selected post")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .people, guru: "Zhao").first == "How did Zhao do this week?",
        "People did not lead with the guru")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .people, guru: nil).first == "How did my gurus do this week?",
        "People without a guru named one")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .accounts, guru: nil).first == "What's in my paper account?",
        "Accounts did not lead with the account")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .today, guru: nil).first == "How do I add Telegram alerts?",
        "Today did not lead with setting up alerts")
    try verifyPanel(
        !AssistantSuggestions.suggestions(for: .today, guru: nil).contains("Why was this post skipped?"),
        "A screen without a selected post asked about this post")
}

@MainActor
private func theContextNamesWhatIsSelected() throws {
    let model = AppModel()
    let post = try assistantPost(sequence: 7, sourceID: "discord:calls:7")
    model.selectedScreen = .activity
    let onActivity = model.assistantContext(selectedPost: post)
    try verifyPanel(
        onActivity == AssistantAskContext(screen: "activity", selectedSourceID: "discord:calls:7"),
        "Activity did not send its selected post: \(onActivity)")
    model.selectedScreen = .today
    let onToday = model.assistantContext(selectedPost: post)
    try verifyPanel(onToday == AssistantAskContext(screen: "today"), "Today sent a post that is not on screen: \(onToday)")
    model.selectedScreen = .gettingStarted
    try verifyPanel(
        model.assistantContext(selectedPost: nil).screen == "gettingStarted", "The screen was not named as the engine expects")
}

@MainActor
private func theContextNamesTheGurusAndTheOneThatIsOpen() throws {
    let model = AppModel()
    model.setupDraft.routes = [
        TradingRouteDraft(guruID: "guru-1a2b3c4d", displayName: "Zhao"),
        TradingRouteDraft(guruID: "guru-5e6f7a8b", displayName: "Ana"),
        TradingRouteDraft(guruID: "guru-1a2b3c4d", displayName: "Zhao"),
        TradingRouteDraft(guruID: "guru-00000000", displayName: "  "),
    ]
    model.selectedScreen = .people
    let nothingOpen = model.assistantContext(selectedPost: nil)
    try verifyPanel(
        nothingOpen.gurus == [
            AssistantGuru(id: "guru-1a2b3c4d", name: "Zhao"), AssistantGuru(id: "guru-5e6f7a8b", name: "Ana"),
        ],
        "The setup's gurus were not named once each: \(nothingOpen.gurus)")
    try verifyPanel(nothingOpen.selectedGuruID == nil, "People with no guru open still named one: \(nothingOpen)")

    model.openGuruID = "guru-5e6f7a8b"
    try verifyPanel(
        model.assistantContext(selectedPost: nil).selectedGuruID == "guru-5e6f7a8b",
        "People did not send the guru whose sheet is open")
    model.selectedScreen = .today
    try verifyPanel(
        model.assistantContext(selectedPost: nil).selectedGuruID == nil, "Today sent a guru that is not on screen")
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
    model.follow(AssistantLink(kind: "post", id: "discord:calls:7", title: "Open in Activity"), activity: [post]) {
        focused = $0
    }
    try verifyPanel(model.selectedScreen == .activity && focused == 7, "A post link did not select the post in Activity")

    focused = nil
    model.selectedScreen = .today
    model.follow(AssistantLink(kind: "post", id: "discord:calls:99", title: "Open in Activity"), activity: [post]) {
        focused = $0
    }
    try verifyPanel(model.selectedScreen == .activity && focused == nil, "A post that is not loaded selected another one")

    model.follow(AssistantLink(kind: "account", id: "paper-main", title: "paper-main"), activity: []) { _ in }
    try verifyPanel(
        model.selectedScreen == .accounts && model.requestedAccountID == "paper-main", "An account link did not open Accounts at it")

    model.follow(AssistantLink(kind: "guru", id: "zhao", title: "zhao"), activity: []) { _ in }
    try verifyPanel(model.selectedScreen == .people && model.requestedGuruID == "zhao", "A guru link did not open their card")

    model.follow(AssistantLink(kind: "elsewhere", id: "x", title: "x"), activity: []) { _ in }
    try verifyPanel(model.selectedScreen == .people, "An unknown link moved the window")
}

@MainActor
private func inSimplifiedChineseTheAssistantAsksAndShowsItsWorkInChinese() throws {
    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    let model = AppModel()
    model.selectedScreen = .people

    preference.select(.english)
    try verifyPanel(model.assistantContext(selectedPost: nil).language == "en", "English did not send en")

    preference.select(.simplifiedChinese)
    try verifyPanel(
        model.assistantContext(selectedPost: nil).language == "zh-Hans", "简体中文 did not send zh-Hans")
    let suggestions = AssistantSuggestions.suggestions(for: .people, guru: "Zhao")
    try verifyPanel(suggestions.first == "Zhao 这周表现怎么样？", "People's first suggestion was \(suggestions)")
    try verifyPanel(
        AssistantSuggestions.suggestions(for: .people, guru: nil).first == "我的信号源这周表现怎么样？",
        "Gurus were not called 信号源")
    for (engine, shown) in [
        ("Looked at your accounts", "已查看你的账户"),
        ("Read paper-main's history", "已读取 paper-main 的账户历史记录"),
        ("Asked you to approve paper-main's recovery change", "已请你批准更改 paper-main 的恢复方式"),
        ("Added up Zhao's calls", "已统计 Zhao 的交易信号"),
        ("Couldn't pause new entries for paper-main", "未能暂停 paper-main 的新开仓"),
        ("Couldn't ask you to approve resuming paper-main", "未能发起恢复 paper-main 开仓的批准请求"),
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
    let payload: [String: Any] = [
        "sequence": sequence,
        "source_id": sourceID,
        "source_revision": 1,
        "source_at": "2026-10-01T12:00:00Z",
        "captured_at": "2026-10-01T12:00:01Z",
        "text": "AMD long",
        "capture_status": "delivered",
        "parse_status": "complete",
        "delivery_status": "delivered",
        "instructions": [],
        "source_event": [
            "event_type": "discord_message", "content": "AMD long", "embeds": [], "attachments": [],
            "attachments_omitted": 0, "capture_status": "complete", "payload_bytes": 0,
        ],
        "destinations": [],
    ]
    return try JSONDecoder().decode(SourceActivity.self, from: JSONSerialization.data(withJSONObject: payload))
}
