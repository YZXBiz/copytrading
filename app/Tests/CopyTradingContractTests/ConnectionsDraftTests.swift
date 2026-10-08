import DesktopCore
import Foundation
import Testing

@MainActor
func runConnectionsDraftTests() throws {
    try savedConfigurationRoundTripsThroughDraft()
    try clearingSecretsRemovesEveryTypedCredential()
    try routesAdoptTheSourceChannel()
    try humanizedValuesAreReadable()
    try statusWordsClassifyAsWholeWords()
    try pickingAProviderSuggestsItsModelButKeepsATypedOne()
    try marketHoursAlsoReadInTheOwnersTime()
    try skippedCallsAreKeptAWeek()
    try orderTimeoutExampleUsesTheAccountsTolerance()
    try alertsSayWhatConnectStillNeeds()
}

/// An alerts sheet names what is missing instead of closing; a secret saved for the same service
/// counts, since a blank field keeps it.
@MainActor
private func alertsSayWhatConnectStillNeeds() throws {
    var draft = ConnectionsDraft()
    draft.notificationService = .telegram
    try #require(draft.missingForAlerts(savedSecret: false) != nil, "An empty Telegram sheet asked for nothing")
    draft.notificationChatID = "12345"
    try #require(draft.missingForAlerts(savedSecret: true) == nil, "A saved bot token was not counted")
    try #require(draft.missingForAlerts(savedSecret: false) != nil, "A missing bot token was not named")
    draft.notificationToken = "fake-bot-token"
    try #require(draft.missingForAlerts(savedSecret: false) == nil, "A filled Telegram sheet still asked for more")
    draft.notificationService = .discord
    draft.notificationToken = ""
    try #require(draft.missingForAlerts(savedSecret: false) != nil, "An empty webhook sheet asked for nothing")
}

@MainActor
private func statusWordsClassifyAsWholeWords() throws {
    let cases: [(String?, StatusTone)] = [
        ("completed", .positive),
        ("broker_connected", .positive),
        ("broker_disconnected", .critical),
        ("not_connected", .inactive),
        ("broker_rate_limited", .caution),
        ("review_required", .caution),
        ("within_limits", .positive),
        ("account_unavailable", .critical),
        ("broker_degraded", .caution),
        ("disabled", .caution),
        ("self_test", .neutral),
        (nil, .inactive),
    ]
    for (code, expected) in cases {
        try #require(StatusTone(code: code) == expected, "\(code ?? "nil") classified as \(StatusTone(code: code))")
    }
}

@MainActor
private func savedConfigurationRoundTripsThroughDraft() throws {
    var seed = ConnectionsDraft()
    seed.channels = "111, 222"
    seed.authors = "333"
    seed.modelName = "claude-sonnet-5"
    seed.accounts = [
        TradingAccountDraft(name: "primary", environment: .paper),
        TradingAccountDraft(name: "live-main", environment: .live),
    ]
    seed.routes = [
        TradingRouteDraft(
            channelID: "111", authorID: "333", guruID: "guru", displayName: "Guru",
            playbook: "  apple means AAPL\n英伟达 means NVDA\n",
            connection: TradingConnectionDraft(accountID: "primary")
        )
    ]
    seed.notificationsEnabled = true
    seed.notificationChatID = "-100"
    let (configuration, _) = try seed.submission()
    try #require(configuration.source.channelIDs == ["111", "222"], "channel IDs were not split and trimmed")
    try #require(
        configuration.profiles.first?.playbook == "apple means AAPL\n英伟达 means NVDA",
        "the playbook lost its lines or kept surrounding blank space"
    )
    try #require(
        configuration.routes.first?.connections.map(\.fullPositionUSD) == [seed.accounts[0].policy.maxSymbolUSD],
        "the guru's full position is not its account's maximum per stock")

    var reloaded = ConnectionsDraft()
    reloaded.load(configuration)
    let (roundTripped, _) = try reloaded.submission()
    try #require(roundTripped == configuration, "loading a saved configuration and resubmitting changed it")
    try #require(reloaded.hasLiveAccounts, "live account was not detected")
}

@MainActor
private func clearingSecretsRemovesEveryTypedCredential() throws {
    var draft = ConnectionsDraft()
    draft.discordToken = "discord"
    draft.providerAPIKey = "provider"
    draft.notificationToken = "telegram"
    draft.accounts = [TradingAccountDraft(name: "primary")]
    draft.accounts[0].key = "key"
    draft.accounts[0].secret = "secret"
    draft.clearSecrets()
    try #require(
        draft.discordToken.isEmpty && draft.providerAPIKey.isEmpty && draft.notificationToken.isEmpty
            && draft.accounts.allSatisfy { $0.key.isEmpty && $0.secret.isEmpty },
        "clearSecrets left a typed credential in memory"
    )
}

@MainActor
private func routesAdoptTheSourceChannel() throws {
    var draft = ConnectionsDraft()
    let following = TradingRouteDraft()
    let pinned = TradingRouteDraft(channelID: "999")
    try #require(draft.effectiveChannel(for: following).isEmpty, "a route had a channel before any was entered")
    // Typing one character at a time must not freeze a partial ID into the route.
    for prefix in ["1", "11", "111 , 222"] {
        draft.channels = prefix
    }
    try #require(draft.effectiveChannel(for: following) == "111", "a route did not follow the first source channel")
    try #require(draft.effectiveChannel(for: pinned) == "999", "a route's own channel was overridden")
}

@MainActor
private func humanizedValuesAreReadable() throws {
    try #require(Humanize.code("review_required") == "Review required", "snake_case code was not humanized")
    try #require(Humanize.code(nil) == "—", "missing code was not shown as a dash")
    try #require(Humanize.usd("not-a-number") == "—", "invalid decimal was shown as money")
    try #require(Humanize.count(1, "account") == "1 account", "singular count was pluralized")
    try #require(Humanize.count(2, "account") == "2 accounts", "plural count was not pluralized")
    try #require(Humanize.timestamp("garbage") == "garbage", "unparseable timestamp was not shown raw")
    try #require(Humanize.fraction("0.1666666666666666666666666667") == "1/6", "exact sixth did not read as 1/6")
    try #require(Humanize.fraction("0.5") == "1/2", "half did not read as 1/2")
    try #require(Humanize.fraction("1") == "1", "whole fraction did not read as 1")
    try #require(Humanize.fraction("0.1666667") == "0.1667", "rounded decimal was mistaken for an exact fraction")
    try #require(Humanize.date("2026-09-28T13:19:05Z") != nil, "ISO timestamp did not parse")
    try #require(Humanize.date("2026-09-28T13:19:05.123Z") != nil, "fractional ISO timestamp did not parse")
}

/// Only a provider pick fills the Model field, and a name the owner typed survives a switch.
@MainActor
private func pickingAProviderSuggestsItsModelButKeepsATypedOne() throws {
    var draft = ConnectionsDraft()
    try #require(draft.modelName.isEmpty, "A new draft started with a model, so its interpreter looked set up")
    let first = draft.provider
    draft.provider = .deepseek
    draft.suggestModel(after: first)
    try #require(draft.modelName == "deepseek-flash", "Picking DeepSeek did not suggest its model")
    draft.provider = .anthropic
    draft.suggestModel(after: .deepseek)
    try #require(draft.modelName == SetupHelp.suggestedModel(for: .anthropic), "The suggestion did not follow a switch")
    draft.modelName = "my-own-model"
    draft.provider = .openai
    draft.suggestModel(after: .anthropic)
    try #require(draft.modelName == "my-own-model", "A switch replaced a name the owner typed")
    draft.provider = .openAICompatible
    draft.modelName = SetupHelp.suggestedModel(for: .openai)
    draft.suggestModel(after: .openai)
    try #require(draft.modelName.isEmpty, "A custom service was given a model it may not have")
}

/// Market hours say New York time, and the owner's own clock when their Mac is elsewhere.
@MainActor
private func marketHoursAlsoReadInTheOwnersTime() throws {
    let october = try #require(ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z"))
    let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let english = Locale(identifier: "en_US")
    let read = { (text: String) in text.replacingOccurrences(of: "\u{202F}", with: " ") }
    let extended = read(
        MarketHoursText.hours([((4, 0), (9, 30)), ((16, 0), (20, 0))], now: october, zone: losAngeles, locale: english))
    try #require(
        extended == "1 AM–6:30 AM and 1 PM–5 PM your time (4 AM–9:30 AM and 4 PM–8 PM New York)",
        "Extended hours read \(extended) in Los Angeles")
    let overnight = read(MarketHoursText.hours([((20, 0), (4, 0))], now: october, zone: shanghai, locale: english))
    try #require(overnight == "8 AM–4 PM your time (8 PM–4 AM New York)", "Overnight hours read \(overnight) in Shanghai")
    let home = read(MarketHoursText.hours([((20, 0), (4, 0))], now: october, zone: newYork, locale: english))
    try #require(home == "8 PM–4 AM New York time", "Hours read \(home) on a Mac in New York")

    let preference = AppLanguagePreference.shared
    let original = preference.language
    defer { preference.select(original) }
    preference.select(.simplifiedChinese)
    let chinese = MarketHoursText.hours(
        [((4, 0), (9, 30)), ((16, 0), (20, 0))], now: october, zone: newYork, locale: Locale(identifier: "zh_Hans_CN"))
    try #require(
        chinese.hasPrefix("纽约时间 ") && chinese.contains("和") && chinese.contains("9:30"),
        "Chinese extended hours read \(chinese)")
}

/// Skipping a waiting call takes it off the owner's list across launches, and the list forgets it
/// a week later, long after the call has expired.
@MainActor
private func skippedCallsAreKeptAWeek() throws {
    let suite = "skipped-calls-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let monday = Date(timeIntervalSince1970: 1_791_200_000)

    SkippedCalls(defaults: defaults, now: monday).skip("discord:1:2", at: monday)

    try #require(SkippedCalls(defaults: defaults, now: monday.addingTimeInterval(3600)).contains("discord:1:2"), "a skip was lost")
    try #require(
        !SkippedCalls(defaults: defaults, now: monday.addingTimeInterval(8 * 24 * 3600)).contains("discord:1:2"),
        "a skip was kept past a week")
}

/// The order-timeout example prices the buy with this account's own tolerance above the guru's
/// price, so it never contradicts the setting above it.
@MainActor
private func orderTimeoutExampleUsesTheAccountsTolerance() throws {
    let atOne = LimitExamples.orderTimeout(maxAboveSignalPct: "1")
    try #require(atOne.contains("**1%**") && atOne.contains("**$202.00 or less**") && atOne.contains("**$205**"), "\(atOne)")
    let atZero = LimitExamples.orderTimeout(maxAboveSignalPct: "0")
    try #require(atZero.contains("**$200.00 or less**") && atZero.contains("**$203**"), "\(atZero)")
    let unreadable = LimitExamples.orderTimeout(maxAboveSignalPct: "")
    try #require(unreadable.contains("**$200.00 or less**"), "\(unreadable)")
}
