import DesktopCore
import Foundation

/// Each account has one switch: Start Copying or Stop Copying. Starting starts copying if it isn't
/// running and turns the account's buys on; stopping turns them off and keeps following the
/// guru's sells for what the account already copied. Stop All pauses copying everywhere.
extension AppModel {
    /// Copying runs, or is on its way up.
    var isCopyingRunning: Bool {
        [.running, .degraded, .starting].contains(tradingStatus?.state)
    }

    /// Copy into one account. A live account can then buy with real money on its own, so it asks
    /// for Touch ID first, once: starting copying already asks for live accounts. With setup
    /// edits waiting and copying off, this is Connections' Start Copying: it checks the edits,
    /// saves them, and starts, instead of starting the saved setup they replace.
    func startCopying(
        into accountID: String, environment: TradingEnvironment?, feature: AccountFeatureModel,
        using operations: (any AccountOperations)? = nil
    ) async {
        if !isCopyingRunning, hasUnsavedSetupChanges, !hasOnlyLimitChanges {
            checkAndStartCopying()
            return
        }
        var confirmed = false
        if !isCopyingRunning, savedTradingConfiguration != nil {
            await startTrading()
            guard isCopyingRunning else { return }
            confirmed = true
        }
        let operations = operations ?? accountActions()
        guard let account = await heldAccount(accountID, feature: feature, using: operations),
            !CopyingState.account(account).isCopying
        else { return }
        if environment == .live, !confirmed {
            do {
                try await confirmOwner(L10n.string("start copying into %@", accountID))
            } catch {
                return
            }
        }
        await feature.control(accountID: accountID, action: .resume, using: operations)
        await feature.refresh(using: operations)
    }

    /// Stop copying into one account: no new buys there; sells of what it copied still follow.
    func stopCopying(
        into accountID: String, feature: AccountFeatureModel, using operations: (any AccountOperations)? = nil
    ) async {
        let operations = operations ?? accountActions()
        await feature.control(accountID: accountID, action: .pause, using: operations)
        await feature.refresh(using: operations)
    }

    /// The menu bar's Start Copying: copy into every account in the saved setup.
    func startCopyingEverywhere(feature: AccountFeatureModel) async {
        if !isCopyingRunning {
            await startTrading()
            guard isCopyingRunning else { return }
        }
        await turnOnEveryAccount(feature: feature)
    }

    /// Applying changes restarts copying, and a restarted account waits for its Start Copying;
    /// the accounts that were copying before the apply copy again without asking.
    func turnOnAccountsCopyingBeforeApply() {
        let ids = accountsCopyingBeforeApply
        accountsCopyingBeforeApply = []
        guard !ids.isEmpty, isCopyingRunning, let accountFeature else { return }
        Task { await turnOn(ids.sorted(), feature: accountFeature) }
    }

    /// After a start from Connections or the menu bar the owner already approved copying into
    /// every account in the setup, live ones included, so each one's buys go on without asking again.
    func turnOnEveryAccount(feature: AccountFeatureModel) async {
        await turnOn(savedTradingConfiguration?.accounts.map(\.id) ?? [], feature: feature)
    }

    private func turnOn(_ accountIDs: [String], feature: AccountFeatureModel) async {
        let operations = accountActions()
        for id in accountIDs {
            guard let account = await heldAccount(id, feature: feature, using: operations),
                !CopyingState.account(account).isCopying
            else { continue }
            await feature.control(accountID: id, action: .resume, using: operations)
        }
        await feature.refresh(using: operations)
    }

    /// The account once the engine holds it: copying that just started opens each account in turn,
    /// so this rereads for a little while before giving up with a plain word.
    private func heldAccount(
        _ accountID: String, feature: AccountFeatureModel, using operations: (any AccountOperations)?
    ) async -> AccountOverview? {
        for attempt in 0..<30 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            await feature.refresh(using: operations)
            if let account = feature.accounts.first(where: { $0.accountID == accountID }),
                account.activeConfiguration, !CopyingState.unheld.contains(account.readiness)
            {
                return account
            }
            if let account = feature.accounts.first(where: { $0.accountID == accountID }),
                account.activeConfiguration, CopyingState.unheld.contains(account.readiness)
            {
                message = L10n.string("%@ can't copy yet: %@.", accountID, Reason.text(account.readiness))
                return nil
            }
        }
        message = L10n.string("Copying started, but %@ isn't ready yet. Try Start Copying again in a moment.", accountID)
        return nil
    }
}
