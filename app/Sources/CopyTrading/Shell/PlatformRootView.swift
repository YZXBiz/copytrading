import DesktopCore
import SwiftUI

struct PlatformRootView: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    /// What happened while the owner was away, shown once after the first read of a session.
    @State private var recap: Recap?
    @State private var hasLookedForRecap = false

    var body: some View {
        Group {
            if model.isTradingUnlocked {
                MainSplitView(model: model, accountFeature: accountFeature)
            } else {
                LockedView(model: model)
            }
        }
        .background {
            WindowSessionMonitor(
                onOpen: { model.windowDidOpen($0) },
                onClose: { model.windowDidClose($0) }
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: model.isTradingUnlocked, initial: true) { _, unlocked in
            if unlocked {
                accountFeature.authorizePrivateEvidence()
            } else {
                accountFeature.clearPrivateEvidence()
                hasLookedForRecap = false
            }
        }
        .onChange(of: accountFeature.lastUpdatedAt) { lookForRecapThenRemember() }
        .sheet(item: $recap) { recap in
            RecapSheet(recap: recap, directory: GuruDirectory(model.savedTradingConfiguration))
        }
    }

    /// The journeys read the real window; a recap from an earlier run would cover it.
    private static var suppressesRecap: Bool {
        #if DEBUG
            UITestLaunch.hidesTips
        #else
            false
        #endif
    }

    /// On the first read after unlocking, a long enough absence gets a recap; every read after that
    /// remembers this moment and what each account was worth.
    private func lookForRecapThenRemember() {
        guard model.isTradingUnlocked, !accountFeature.accounts.isEmpty else { return }
        if !hasLookedForRecap {
            hasLookedForRecap = true
            if !Self.suppressesRecap, let since = RecapMemory.lastSeen, Date.now.timeIntervalSince(since) >= RecapMemory.awayLongEnough {
                let now = Date.now
                let skipped = model.skippedCalls
                let calls: [WaitingCall] = accountFeature.activity.compactMap { WaitingCall($0) }
                let waiting = calls.filter { !$0.hasExpired(at: now) && !skipped.contains($0.source.sourceID) }.count
                let found = Recap.since(
                    since, activity: accountFeature.activity, accounts: accountFeature.accounts,
                    equities: RecapMemory.equities, waiting: waiting)
                if !found.isEmpty { recap = found }
            }
        }
        RecapMemory.record(accountFeature.accounts)
    }
}
