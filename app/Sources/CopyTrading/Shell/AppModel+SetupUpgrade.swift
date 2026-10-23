import DesktopCore
import Foundation

extension AppModel {
    /// Carry a setup an earlier version saved into this version, once, keys and all, then start
    /// copying if the owner asked for it on launch. A step may need what only the accounts'
    /// records know, so the engine is up first; nothing starts copying until this returns.
    func upgradeSavedSetup(
        in store: TradingConfigurationStore,
        recordedRecovery: () async throws -> [String: RecoveryPreference],
        revision: @escaping @Sendable (TradingConfiguration) async throws -> String
    ) async {
        defer { setupAwaitsUpgrade = false }
        do {
            let facts = SetupUpgrade.Facts(recoveryPreferences: try await recordedRecovery())
            _ = try await store.upgradeOlderVersion(facts: facts, revision: revision)
            let saved = try store.load()
            savedTradingConfiguration = saved?.configuration
            hasTradingSecrets = saved != nil
            syncSetupDraftWithSaved()
        } catch {
            message = L10n.string(
                "Your setup from the last version couldn't be carried over: %@ It's kept as it was; quit and open CopyTrading to try again.",
                Self.userMessage(for: error))
            return
        }
        setupAwaitsUpgrade = false
        await startCopyingOnLaunchIfWanted()
    }

    /// Each account's after-restart choice as its record last held it.
    static func recordedRecoveryPreferences(using actions: EngineActions) async throws -> [String: RecoveryPreference] {
        var preferences: [String: RecoveryPreference] = [:]
        var before: String?
        repeat {
            let page = try await actions.accounts(beforeAccountID: before, limit: 100)
            for account in page.items { preferences[account.accountID] = account.recoveryPreference }
            before = page.nextBeforeAccountID
        } while before != nil
        return preferences
    }
}
