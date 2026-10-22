import DesktopCore

/// An app that comes back after a quit, a crash, or a Mac restart is paused, unless the owner chose
/// to start copying on launch or an update relaunched it while copying. If copying was on when it
/// last stopped, the owner is told so with a macOS notification, again every half hour while it
/// stays paused during trading hours, and for as long as it holds in a banner (window and menu
/// bar) that starts copying in one press.
extension AppModel {
    /// Copying was on when CopyTrading last stopped and is paused now, with a setup to start and
    /// nothing about to start it: not an owner-chosen launch start, and not one already underway.
    var showsCopyingStopped: Bool {
        copyingStoppedWithQuit && savedTradingConfiguration != nil && tradingStatus?.state == .paused
            && !isTradingCommandPending && !startsCopyingOnItsOwn
    }

    private var startsCopyingOnItsOwn: Bool {
        wantsCopyingOnLaunch && canStartCopyingOnLaunch && !didStartCopyingOnLaunch
    }

    /// Called with every status the engine reports: tells the owner, and again every half hour
    /// while copying stays paused during trading hours, when a guru's calls are being missed; ends
    /// the notice when copying runs again; and remembers whether copying is on for the next launch.
    func trackCopyingAcrossLaunches() {
        let state = tradingStatus?.state
        let now = clock()
        if showsCopyingStopped,
            copyingStoppedAnnouncedAt.map({ now.timeIntervalSince($0) >= 30 * 60 && TradingHours.contains(now) }) ?? true
        {
            copyingStoppedAnnouncedAt = now
            announceCopyingStopped()
        }
        if copyingStoppedWithQuit, [.running, .degraded, .starting].contains(state) {
            copyingStoppedWithQuit = false
        }
        copyingMemory.observe(state)
    }

    /// The owner has seen it and wants copying left stopped.
    func dismissCopyingStopped() {
        copyingStoppedWithQuit = false
    }
}
