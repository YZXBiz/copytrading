import CopyTradingTestSupport
import DesktopCore
import Foundation
import Testing

/// Copying never starts without the owner, so when CopyTrading comes back paused after copying was
/// on, the owner is told once and can start it in one press. A deliberate Stop Copying is not that.
@MainActor
func runCopyingStoppedTests() throws {
    try copyingMemoryFollowsWhatTheEngineReports()
    try aQuitUnderCopyingIsToldOnTheNextLaunch()
    try aDeliberateStopIsNotToldOnTheNextLaunch()
    try aCrashUnderCopyingIsToldOnTheNextLaunch()
    try aLaunchThatStartsCopyingItselfIsNotToldUntilItFails()
    try startingCopyingOrDismissingEndsTheNotice()
}

/// A throwaway preferences domain, so a check never touches the owner's.
private func scratchDefaults() throws -> (defaults: UserDefaults, remove: () -> Void) {
    let name = "dev.copytrading.tests.copying-memory.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name), "no scratch preferences")
    return (defaults, { defaults.removePersistentDomain(forName: name) })
}

private func status(_ state: TradingRunState) throws -> TradingStatus {
    try TradingStatusBuilder(state).connected().build()
}

private func savedPaperSetup() throws -> TradingConfiguration {
    let profile = try TradingProfileBuilder().build(TradingProfileDraft(guruID: "alex", displayName: "Alex"))
    return TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["123"]),
        provider: TradingProviderConfiguration(name: .deepseek, model: "deepseek-flash"),
        accounts: [TradingAccountConfiguration(id: "primary", environment: .paper)],
        profiles: [profile],
        routes: [
            TradingRouteConfiguration(
                channelID: "123", authorID: nil, guruID: "alex", profileRevision: profile.profileRevision,
                connections: [TradingRouteConnection(accountID: "primary", fullPositionUSD: "600")])
        ])
}

/// One launch of the app on the same preferences: a model that reads what the last one left.
@MainActor
private func launch(_ defaults: UserDefaults) throws -> (model: AppModel, announced: () -> Int) {
    let model = AppModel(copyingMemory: CopyingMemory(defaults: defaults))
    model.savedTradingConfiguration = try savedPaperSetup()
    var announced = 0
    model.announceCopyingStopped = { announced += 1 }
    return (model, { announced })
}

/// What the memory keeps: copying seen on stays on through a missing or failed status, which is
/// all a quit or a crash leaves behind; only a paused status (Stop Copying) clears it.
@MainActor
private func copyingMemoryFollowsWhatTheEngineReports() throws {
    let (defaults, remove) = try scratchDefaults()
    defer { remove() }
    let memory = CopyingMemory(defaults: defaults)
    try #require(!memory.wasOn, "a first launch remembered copying")

    memory.observe(.paused)
    try #require(!memory.wasOn, "a paused engine at launch remembered copying")
    for state in [TradingRunState.starting, .running, .degraded] {
        memory.observe(.paused)
        memory.observe(state)
        try #require(memory.wasOn, "\(state) was not remembered as copying")
    }
    memory.observe(nil)
    memory.observe(.failed)
    try #require(memory.wasOn, "the engine going away forgot that copying was on")
    try #require(CopyingMemory(defaults: defaults).wasOn, "the next launch did not read it")

    memory.observe(.pausing)
    try #require(!memory.wasOn, "Stop Copying under way left copying remembered")
    memory.observe(.running)
    memory.observe(.paused)
    try #require(!memory.wasOn, "a paused status did not clear it")
    try #require(!CopyingMemory(defaults: defaults).wasOn, "the next launch read a cleared memory as on")
}

@MainActor
private func aQuitUnderCopyingIsToldOnTheNextLaunch() throws {
    let (defaults, remove) = try scratchDefaults()
    defer { remove() }

    let last = try launch(defaults)
    try #require(!last.model.showsCopyingStopped, "a first launch showed the notice")
    last.model.tradingStatus = try status(.running)
    // The quit: the app stops reporting; the engine's own stop is never read back as a pause.
    last.model.tradingStatus = nil

    let next = try launch(defaults)
    try #require(next.model.copyingStoppedWithQuit, "the next launch did not know copying was on")
    try #require(!next.model.showsCopyingStopped, "the notice showed before the engine reported")
    next.model.tradingStatus = try status(.paused)
    try #require(next.model.showsCopyingStopped, "a paused launch after copying did not show the notice")
    try #require(next.announced() == 1, "the owner was not notified exactly once")
    // The status is read again every couple of seconds; one notification per launch.
    next.model.tradingStatus = try status(.paused)
    next.model.tradingStatus = try status(.paused)
    try #require(next.announced() == 1, "the notification repeated with every status")
    try #require(next.model.showsCopyingStopped, "the banner went away on its own while copying stayed paused")
    try #require(!CopyingMemory(defaults: defaults).wasOn, "a paused launch left copying remembered as on")

    // Quitting again without starting is not "copying was on": the next launch says nothing.
    next.model.tradingStatus = nil
    let third = try launch(defaults)
    third.model.tradingStatus = try status(.paused)
    try #require(!third.model.showsCopyingStopped && third.announced() == 0, "a second paused launch told the owner again")
}

@MainActor
private func aDeliberateStopIsNotToldOnTheNextLaunch() throws {
    let (defaults, remove) = try scratchDefaults()
    defer { remove() }

    let last = try launch(defaults)
    last.model.tradingStatus = try status(.running)
    last.model.tradingStatus = try status(.pausing)
    last.model.tradingStatus = try status(.paused)
    last.model.tradingStatus = nil

    let next = try launch(defaults)
    next.model.tradingStatus = try status(.paused)
    try #require(!next.model.copyingStoppedWithQuit, "a Stop Copying was remembered as copying")
    try #require(!next.model.showsCopyingStopped, "a deliberate Stop Copying showed the notice")
    try #require(next.announced() == 0, "a deliberate Stop Copying sent a notification")
}

/// A crash leaves no goodbye, so nothing in the app's exit can be what remembers: the status
/// that said copying was on already did, and an engine that died with the app reports nothing.
@MainActor
private func aCrashUnderCopyingIsToldOnTheNextLaunch() throws {
    let (defaults, remove) = try scratchDefaults()
    defer { remove() }

    let last = try launch(defaults)
    last.model.tradingStatus = try status(.running)
    // No further call: the process is gone, as after a crash or a power cut.

    let next = try launch(defaults)
    next.model.tradingStatus = try status(.paused)
    try #require(next.model.showsCopyingStopped, "a crash under copying was not told on the next launch")
    try #require(next.announced() == 1, "a crash under copying sent no notification")
}

/// Settings → General can start copying on its own (paper only), and an update does too. Those
/// launches say nothing while the start is coming, and say so if it never happens.
@MainActor
private func aLaunchThatStartsCopyingItselfIsNotToldUntilItFails() throws {
    let (defaults, remove) = try scratchDefaults()
    defer { remove() }
    let key = AppModel.resumesAfterUpdateKey
    UserDefaults.standard.removeObject(forKey: key)
    defer { UserDefaults.standard.removeObject(forKey: key) }

    let last = try launch(defaults)
    last.model.tradingStatus = try status(.running)
    last.model.rememberCopyingForRelaunch()

    let next = try launch(defaults)
    try #require(next.model.wantsCopyingOnLaunch, "the update relaunch would not start copying")
    next.model.tradingStatus = try status(.paused)
    try #require(!next.model.showsCopyingStopped, "the notice showed while the launch start was coming")
    try #require(next.announced() == 0, "a launch that starts copying itself sent a notification")

    next.model.didStartCopyingOnLaunch = true
    next.model.tradingStatus = try status(.paused)
    try #require(next.model.showsCopyingStopped, "a launch start that left copying paused did not show the notice")
    try #require(next.announced() == 1, "a launch start that left copying paused sent no notification")
}

@MainActor
private func startingCopyingOrDismissingEndsTheNotice() throws {
    let (defaults, remove) = try scratchDefaults()
    defer { remove() }
    let last = try launch(defaults)
    last.model.tradingStatus = try status(.running)

    let started = try launch(defaults)
    started.model.tradingStatus = try status(.paused)
    try #require(started.model.showsCopyingStopped, "the notice did not show")
    started.model.tradingStatus = try status(.starting)
    started.model.tradingStatus = try status(.running)
    started.model.tradingStatus = try status(.paused)
    try #require(!started.model.showsCopyingStopped, "the notice came back after the owner stopped what they started")

    let last2 = try launch(defaults)
    last2.model.tradingStatus = try status(.running)
    let dismissed = try launch(defaults)
    dismissed.model.tradingStatus = try status(.paused)
    dismissed.model.dismissCopyingStopped()
    try #require(!dismissed.model.showsCopyingStopped, "Dismiss left the notice up")

    let noSetup = try launch(defaults)
    noSetup.model.copyingStoppedWithQuit = true
    noSetup.model.savedTradingConfiguration = nil
    noSetup.model.tradingStatus = try status(.paused)
    try #require(!noSetup.model.showsCopyingStopped, "the notice offered Start Copying with no setup to start")
}
