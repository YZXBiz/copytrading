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

    /// Limits are all the draft changes, so they save when the account sheet closes and never
    /// wait on Apply Changes; once a save is refused they wait like any other change.
    var hasOnlyLimitChanges: Bool {
        guard !limitsSaveRefused, !setupDraft.hasTypedSecrets, let saved = savedTradingConfiguration,
            let edited = try? setupDraft.submission().0
        else { return false }
        return edited.limitOnlyChanges(from: saved) != nil
    }

    /// Connections shows its start card while there is something to set up, check, or start.
    var hasSetupToStart: Bool {
        savedTradingConfiguration == nil
            || (hasUnsavedSetupChanges && !hasOnlyLimitChanges) || isValidatingTrading || isActivatingTrading || tradingValidation != nil
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
        limitsSaveRefused = false
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

    func editAccount(named accountID: String, focusingEntryTolerance: Bool = false) {
        guard let account = setupDraft.accounts.first(where: { $0.name.trimmed == accountID }) else { return }
        editorFocusesEntryTolerance = focusingEntryTolerance
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
    /// in the draft, so a failed check never makes the owner type them again. When only the
    /// readings are left to look over, it shows them, and pressed beside them it approves them.
    func checkAndStartCopying() {
        guard !isApplyingChanges else { return }
        if isCopyingSavedSetup {
            applyChangesWhileCopying()
            return
        }
        if awaitsExampleReview && checkedSetupSignature == setupDraft.signature {
            guard isShowingSetupCheck else {
                isShowingSetupCheck = true
                return
            }
            acknowledgeProfileExamples()
        }
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

    /// Start Copying can run: the four steps are filled in, copying is paused or runs the saved
    /// setup (then the button applies the changes), and no check or start is under way.
    var canCheckAndStart: Bool {
        isFilledInToCheck && (tradingStatus?.state == .paused || isCopyingSavedSetup)
            && !isValidatingTrading && !isActivatingTrading && !isTradingCommandPending && !isApplyingChanges
    }

    /// Everything a check needs is filled in. A connection whose last check failed doesn't
    /// block it: Start Copying checks every connection again, and a one-off timeout clears.
    private var isFilledInToCheck: Bool {
        SetupProgress(
            draft: setupDraft, hasSavedKeys: hasTradingSecrets, hasSavedProviderKey: hasSavedProviderKey,
            savedKeyAccountIDs: savedKeyAccountIDs, isSetUp: savedTradingConfiguration != nil
        ).isReadyToCheck
    }

    /// Copying runs the saved setup, so the setup's changes are applied rather than started.
    var isCopyingSavedSetup: Bool {
        savedTradingConfiguration != nil && [.running, .degraded].contains(tradingStatus?.state)
    }

    /// The engine takes a new setup only while paused, so the pause is kept as short as the
    /// check and the start. The examples are read first, while copying runs on; when they need a
    /// look, the readings wait for the owner with copying still running, and pressing Start
    /// Copying beside them pauses, checks, and starts. Posts that arrive during the pause are read
    /// when copying starts again.
    private func applyChangesWhileCopying() {
        let submission: (TradingConfiguration, TradingSecrets)
        do {
            submission = try setupDraft.submission()
        } catch {
            message = Self.setupProblem(for: error)
            return
        }
        let readingsShown =
            checkedSetupSignature == setupDraft.signature && !profileExampleReviews.isEmpty
            && profileExampleReviews.values.allSatisfy(\.automaticActivationAllowed)
        if readingsShown && !isShowingSetupCheck {
            isShowingSetupCheck = true
            return
        }
        checkedSetupSignature = setupDraft.signature
        applyChangesTask?.cancel()
        isApplyingChanges = true
        applyChangesTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isApplyingChanges = false }
            let reviews: [String: ProfileExampleReview]
            if readingsShown {
                // Pressed beside the readings: the owner's yes to them.
                self.profileExamplesAcknowledged = true
                reviews = self.profileExampleReviews
            } else {
                let read = await self.validateTradingSettings(
                    submission.0, enteredSecrets: submission.1, reviewOnly: true)
                guard read, !Task.isCancelled else { return }
                guard self.profileExampleReviews.isEmpty else {
                    self.isShowingSetupCheck = true
                    return
                }
                reviews = [:]
            }
            self.isPausedToApplyChanges = true
            await self.pauseTrading()
            guard await self.waitUntilPaused() else {
                guard !Task.isCancelled else { return }
                self.isPausedToApplyChanges = false
                self.message = L10n.string("Copying didn't pause, so your changes weren't applied. Try again.")
                return
            }
            guard !Task.isCancelled else { return }
            await self.checkThenStart(submission.0, enteredSecrets: submission.1, reviewed: reviews)
            guard !Task.isCancelled else { return }
            await self.resumeSavedSetupIfPausedForChanges()
        }
    }

    /// Pausing answers "pausing" while open orders and the source wind down; wait for paused.
    private func waitUntilPaused() async -> Bool {
        guard let control = connectionChecker else { return false }
        for _ in 0..<120 {
            if tradingStatus?.state == .paused { return true }
            guard [.pausing, .running, .degraded].contains(tradingStatus?.state), !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(500))
            if let status = try? await control.tradingStatus() { tradingStatus = status }
        }
        return tradingStatus?.state == .paused
    }

    /// Changes that did not start leave the saved setup copying again. What the check found stays
    /// readable in Setup Check, and the rows in Connections keep each connection's result.
    func resumeSavedSetupIfPausedForChanges() async {
        guard isPausedToApplyChanges, !isValidatingTrading, !isActivatingTrading, tradingStatus?.state == .paused
        else { return }
        isPausedToApplyChanges = false
        let failedCheck = tradingValidation.flatMap { $0.report.activatable ? nil : $0 }
        cancelTradingActivation()
        await startTrading(resumingSavedSetup: true)
        if let failedCheck, tradingStatus?.state != .paused {
            tradingValidation = failedCheck
            isShowingSetupCheck = true
        }
        if message == nil {
            message = L10n.string("Your changes weren't saved, so copying continues with the saved setup.")
        }
    }

    /// Locking or closing the window while changes are applied: the apply stops, and once copying
    /// has finished pausing the saved setup copies again, before access is gone.
    func finishInterruptedApply(_ applying: Task<Void, Never>?) async {
        guard let applying else { return }
        await applying.value
        guard isPausedToApplyChanges else { return }
        _ = await waitUntilPaused()
        await resumeSavedSetupIfPausedForChanges()
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
        prefillEmptySetup()
    }

    /// A debug build started by `make dev-app` begins an empty setup from the owner's test keys.
    func prefillEmptySetup() {
        #if DEBUG
            if savedTradingConfiguration == nil, let prefill = DevPrefill.launch {
                prefill.fill(&setupDraft)
            }
        #endif
    }

    /// A new setup was saved and copying started: show the owner where its results will appear.
    /// Applied changes leave the owner where they made them, with a word that they took effect.
    func didStartCopyingNewSetup() {
        let appliedChanges = isPausedToApplyChanges
        isPausedToApplyChanges = false
        checkedSetupSignature = nil
        isShowingSetupCheck = false
        profileExampleReviews = [:]
        profileExamplesAcknowledged = false
        guard !appliedChanges else {
            message = L10n.string("Your changes are saved, and copying uses them now.")
            return
        }
        message = nil
        copyingStartedAt = .now
        selectedScreen = homeScreen
    }

    /// Fills the setup from a file the owner chose in the open panel. Only the draft changes:
    /// Connect and Start Copying check everything before it is saved. Nothing from the file is
    /// logged or kept, and the summary names fields, never values.
    func importSetup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= SetupImport.maximumBytes,
            let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8)
        else {
            message = L10n.string("That file isn't a setup CopyTrading can read. Choose a small text file with your keys.")
            return
        }
        let setup = SetupImport(text: text)
        guard !setup.isEmpty else {
            message = L10n.string("Nothing in that file looks like a setup: no Discord, model, or Alpaca lines.")
            return
        }
        setupEditor = nil
        setup.apply(to: &setupDraft)
        selectedScreen = .connections
        setupImportResult = SetupImportResult(fileURL: url, filled: setup.filled, missing: setup.missing)
    }

    /// The imported file to the Trash, once its keys are in the setup.
    func trashImportedFile() {
        guard let url = setupImportResult?.fileURL else { return }
        setupImportResult = nil
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            message = L10n.string("CopyTrading couldn't move the file to the Trash. Delete it yourself once you've started copying.")
        }
    }

    /// Starts the setup tour on Connections, at the first thing still to do.
    func startSetupTour() {
        setupEditor = nil
        isTouringSetup = true
        selectedScreen = .connections
    }

    /// Ends the tour, and remembers it so a later launch doesn't start it again on its own.
    func endSetupTour() {
        isTouringSetup = false
        UserDefaults.standard.set(true, forKey: Self.setupTourEndedKey)
    }

    static let setupTourEndedKey = "setupTour.ended"

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
