import DesktopCore

extension AppModel {
    /// Resumes an account's entries from Accounts or from a held buy in Activity. A live account
    /// can then buy with real money on its own, so it asks for Touch ID first; afterwards Activity
    /// rereads, so a held buy shows whether it was copied.
    func resumeEntries(
        accountID: String, environment: TradingEnvironment?, feature: AccountFeatureModel,
        using operations: (any AccountOperations)? = nil
    ) async {
        let operations = operations ?? accountActions()
        if environment == .live {
            do {
                try await confirmOwner(L10n.string("allow new entries in %@", accountID))
            } catch {
                return
            }
        }
        await feature.control(accountID: accountID, action: .resume, using: operations)
        await feature.refresh(using: operations)
    }
}
