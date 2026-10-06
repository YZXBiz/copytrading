/// How far a setup has come, read from the draft and what is saved, so the guide ticks itself
/// as the owner types rather than asking them to tick anything.
struct SetupProgress: Equatable {
    let done: Set<SetupStep>

    /// - Parameters:
    ///   - hasSavedKeys: the Discord token is in the Keychain from a saved setup.
    ///   - hasSavedProviderKey: the saved model key is for the provider the draft names.
    ///   - savedKeyAccountIDs: accounts whose Alpaca keys are in the Keychain.
    ///   - isSetUp: a setup has been checked, saved, and started at least once.
    ///   - failed: connections whose latest check failed, which keep their step from ticking.
    init(
        draft: ConnectionsDraft, hasSavedKeys: Bool, hasSavedProviderKey: Bool, savedKeyAccountIDs: Set<String>,
        isSetUp: Bool, failed: Set<ConnectionCheckSubject> = []
    ) {
        var done: Set<SetupStep> = []
        if !draft.sourceChannelIDs.isEmpty && (!draft.discordToken.isEmpty || hasSavedKeys) && !failed.contains(.discord) {
            done.insert(.discord)
        }
        let hasModelKey = !draft.provider.requiresAPIKey || !draft.providerAPIKey.isEmpty || hasSavedProviderKey
        if !draft.modelName.trimmed.isEmpty && hasModelKey && draft.providerConfiguration.baseURLProblem == nil
            && !failed.contains(.interpreter)
        {
            done.insert(.interpreter)
        }
        let accountsWithKeys = Set(
            draft.accounts.filter { account in
                let name = account.name.trimmed
                return !name.isEmpty && !failed.contains(.account(name))
                    && ((!account.key.isEmpty && !account.secret.isEmpty) || savedKeyAccountIDs.contains(name))
            }.map { $0.name.trimmed })
        if !accountsWithKeys.isEmpty {
            done.insert(.account)
        }
        let accountIDs = Set(draft.accountIDs)
        let readyGuru = draft.routes.contains { route in
            !route.displayName.trimmed.isEmpty
                && !draft.effectiveChannel(for: route).isEmpty
                && route.connection.map { accountIDs.contains($0.accountID.trimmed) } == true
        }
        if readyGuru {
            done.insert(.guru)
        }
        if isSetUp {
            done.insert(.start)
        }
        self.done = done
    }

    var completed: Int { done.count }
    var total: Int { SetupStep.allCases.count }
    var fraction: Double { Double(completed) / Double(total) }
    var isComplete: Bool { completed == total }

    /// The first step still to do, which the guide opens for the owner.
    var next: SetupStep? { SetupStep.allCases.first { !done.contains($0) } }

    /// Everything a check needs is in place.
    var isReadyToCheck: Bool { done.isSuperset(of: [.discord, .interpreter, .account, .guru]) }

    func isDone(_ step: SetupStep) -> Bool { done.contains(step) }
}
