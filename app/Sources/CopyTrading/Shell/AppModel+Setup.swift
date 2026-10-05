import DesktopCore
import Foundation

/// Editing the setup, all of it on Connections: one draft, and one Start Copying that checks it
/// and starts.
extension AppModel {
    static var pendingSetupMessage: String { L10n.string("Starting your new setup…") }
    static var changedAfterCheckMessage: String { L10n.string("The setup changed after it was checked. Check it again.") }

    /// The draft differs from what is saved: typed keys, edits, or a first setup in progress.
    var hasUnsavedSetupChanges: Bool {
        if setupDraft.hasTypedSecrets { return true }
        guard let saved = savedTradingConfiguration else { return !setupDraft.isEmpty }
        guard let edited = try? setupDraft.submission().0 else { return true }
        return edited != saved
    }

    /// Connections shows its start card while there is something to set up, check, or start.
    var hasSetupToStart: Bool {
        savedTradingConfiguration == nil
            || hasUnsavedSetupChanges || isValidatingTrading || isActivatingTrading || tradingValidation != nil
            || !profileExampleReviews.isEmpty
    }

    /// How far the setup has come, for the guide, Today, and the sidebar.
    var setupProgress: SetupProgress {
        SetupProgress(
            draft: setupDraft, hasSavedKeys: hasTradingSecrets, hasSavedProviderKey: hasSavedProviderKey,
            savedKeyAccountIDs: savedKeyAccountIDs, isSetUp: savedTradingConfiguration != nil,
            failed: Set(connectionChecks.keys.filter { connectionCheckResult($0)?.check?.state == .failed }))
    }

    /// The saved model key belongs to the provider the draft names, so a blank key field keeps it.
    var hasSavedProviderKey: Bool {
        hasTradingSecrets && savedTradingConfiguration?.provider.name == setupDraft.provider
    }

    /// The interpreter has what it needs to read: a typed key, a saved one, or none required.
    var interpreterHasKey: Bool {
        !setupDraft.provider.requiresAPIKey || !setupDraft.providerAPIKey.isEmpty || hasSavedProviderKey
    }

    /// Accounts whose broker keys are already in the Keychain; a blank key field keeps those.
    var savedKeyAccountIDs: Set<String> {
        guard hasTradingSecrets else { return [] }
        return Set(savedTradingConfiguration?.accounts.map(\.id) ?? [])
    }

    /// Every check passed, the readings were looked at, and nothing changed since.
    var canStartCopyingFromCheck: Bool {
        tradingValidation?.report.activatable == true
            && tradingValidation?.activationToken != nil
            && !isActivatingTrading
            && profileExampleReviews.values.allSatisfy(\.automaticActivationAllowed)
            && (profileExampleReviews.isEmpty || profileExamplesAcknowledged)
            && checkedSetupSignature == setupDraft.signature
    }

    /// Every connection passed and the examples read as expected; only looking them over is left.
    var awaitsExampleReview: Bool {
        tradingValidation?.report.activatable == true
            && tradingValidation?.activationToken != nil
            && !profileExampleReviews.isEmpty
            && profileExampleReviews.values.allSatisfy(\.automaticActivationAllowed)
            && !profileExamplesAcknowledged
    }

    /// Refills the draft from the saved setup when that setup changed, never over unsaved edits
    /// to the same setup. Keys typed for it are now in the Keychain, so they leave the draft.
    func syncSetupDraftWithSaved() {
        guard let saved = savedTradingConfiguration, saved != setupDraftSource else { return }
        setupEditor = nil
        setupDraft.load(saved)
        setupDraft.clearSecrets()
        setupDraftSource = saved
    }

    /// A new account; the first guru that copies into nothing yet copies into it, since an
    /// account copies one guru.
    func addAccount(_ environment: TradingEnvironment = .paper) {
        let account = TradingAccountDraft(name: setupDraft.nextAccountName, environment: environment)
        setupDraft.accounts.append(account)
        if let index = setupDraft.routes.firstIndex(where: { $0.connection == nil }) {
            setupDraft.routes[index].connection = TradingConnectionDraft(accountID: account.name)
        }
        setupEditor = .account(account.id)
    }

    /// Renaming an account keeps every guru that copies into it pointed at it.
    func renameAccountReferences(from oldName: String, to newName: String) {
        guard !oldName.isEmpty, oldName != newName else { return }
        for route in setupDraft.routes.indices
        where setupDraft.routes[route].connection?.accountID.trimmed == oldName {
            setupDraft.routes[route].connection?.accountID = newName
        }
    }

    /// A new guru copies into the first account no other guru copies into, until the owner
    /// chooses otherwise.
    func addGuru() {
        var route = TradingRouteDraft()
        if let free = setupDraft.accountChoices(for: route).first {
            route.connection = TradingConnectionDraft(accountID: free)
        }
        setupDraft.routes.append(route)
        setupEditor = .route(route.id)
    }

    func editAccount(named accountID: String) {
        guard let account = setupDraft.accounts.first(where: { $0.name.trimmed == accountID }) else { return }
        setupEditor = .account(account.id)
    }

    func editGuru(_ guruID: String) {
        guard let route = setupDraft.routes.first(where: { $0.guruID.trimmed == guruID }) else { return }
        setupEditor = .route(route.id)
    }

    func removeAccount(named accountID: String) {
        setupDraft.accounts.removeAll { $0.name.trimmed == accountID }
    }

    func removeGuru(_ guruID: String) {
        setupDraft.routes.removeAll { $0.guruID.trimmed == guruID }
    }

    /// The one Start Copying: a setup already checked starts; otherwise every connection and
    /// example is checked first, then copying starts if nothing needs the owner. Typed keys stay
    /// in the draft, so a failed check never makes the owner type them again.
    func checkAndStartCopying() {
        if canStartCopyingFromCheck {
            Task { await activateValidatedTradingSettings() }
            return
        }
        do {
            let (configuration, secrets) = try setupDraft.submission()
            checkedSetupSignature = setupDraft.signature
            beginTradingValidation(configuration, enteredSecrets: secrets, thenStart: true)
        } catch {
            message = Self.setupProblem(for: error)
        }
    }

    /// Start Copying can run: the four steps are filled in, copying is paused, and no check or
    /// start is under way.
    var canCheckAndStart: Bool {
        setupProgress.isReadyToCheck && tradingStatus?.state == .paused && !isValidatingTrading
            && !isActivatingTrading
    }

    /// Start Copying must save exactly what was checked, so any later edit discards the check.
    func setupDraftDidChange() {
        guard let checked = checkedSetupSignature, checked != setupDraft.signature, !isActivatingTrading else { return }
        cancelTradingActivation(message: Self.changedAfterCheckMessage)
    }

    func discardSetupChanges() {
        cancelTradingActivation()
        setupEditor = nil
        setupDraft = ConnectionsDraft()
        setupDraftSource = nil
        syncSetupDraftWithSaved()
    }

    /// A new setup was saved and copying started: show the owner where its results will appear.
    func didStartCopyingNewSetup() {
        checkedSetupSignature = nil
        isShowingSetupCheck = false
        profileExampleReviews = [:]
        profileExamplesAcknowledged = false
        message = nil
        copyingStartedAt = .now
        selectedScreen = .today
    }

    /// Opens a connection's settings on Connections, with its first field ready for typing.
    func open(_ connection: ConnectionKind) {
        requestedConnection = connection
        selectedScreen = .connections
    }

    static func setupProblem(for error: any Error) -> String {
        switch error {
        case TradingProfileBuilderError.invalidIdentity:
            L10n.string("Each guru needs a name.")
        case TradingProfileBuilderError.invalidProfile:
            L10n.string("Each guru needs a message prefix, and a playbook under %@ characters.", tradingPlaybookMaxLength.formatted())
        case TradingProfileBuilderError.invalidExample:
            L10n.string("Check each guru's examples: each needs a message, a ticker, and a fraction between 0 and 1 if given.")
        case let error as TradingSettingsError:
            Self.userMessage(for: error)
        default:
            L10n.string("Check each guru's sizing and examples, then start copying again.")
        }
    }
}
