import DesktopCore
import Foundation

/// `copytrading setup …`: the CLI edits the same draft Connections edits, and `setup apply` is
/// Start Copying on it. The app answers these requests itself, so a key goes from the request
/// to the draft and then the Keychain, never to the engine; the engine only decides whether a
/// request may run, and makes anything that touches a live account a proposal.
extension AppModel {
    /// Answers one setup request line with exactly one contract response line.
    func answerAgentSetup(line: String, context: AgentRequestContext) async -> String {
        let request: AgentSetupRequest
        do {
            request = try AgentSetupRequest(line: line)
        } catch {
            // Refused here, but the engine's trail still records who sent it.
            if let operation = AgentSetupOperation.of(line: line), let operations = agentProposalOperations() {
                _ = try? await operations.authorizeSetup(
                    AgentSetupAuthorizationRequest(
                        operation: operation, requestID: error.requestID, apply: nil, invalid: true),
                    context: context)
            }
            return AgentSetupResponse.errorLine(
                requestID: error.requestID, code: "invalid_request", message: error.message)
        }
        guard let operations = agentProposalOperations() else {
            return Self.agentSetupError(request, .engineNotRunning)
        }
        syncSetupDraftWithSaved()
        // What the engine decides about is the draft as it is now: its facts and its signature are
        // taken together, before the engine is asked, so an edit made while it decides is never
        // part of what it allowed or what the owner approves.
        let start: Bool
        if case .apply(let wanted) = request.edit { start = wanted } else { start = false }
        let facts = request.operation == .apply ? agentApplyFacts(start: start) : nil
        let decided = setupDraft.signature
        let authorization: AgentSetupAuthorization
        do {
            authorization = try await operations.authorizeSetup(
                AgentSetupAuthorizationRequest(operation: request.operation, requestID: request.requestID, apply: facts),
                context: context)
        } catch {
            return Self.agentSetupError(request, .engineProblem(error))
        }
        if case .answered(let answer) = authorization {
            if facts != nil, let proposalID = Self.proposalID(in: answer) {
                agentSetupProposals[proposalID] = (decided, start)
                await refreshAssistantProposals()
            }
            return answer
        }
        if facts != nil, setupDraft.signature != decided {
            return Self.agentSetupError(
                request,
                .conflict("The setup changed while CopyTrading was checking the request. Run `copytrading setup apply` again."))
        }
        do {
            return AgentSetupResponse.line(requestID: request.requestID, result: try await performAgentSetup(request.edit))
        } catch let problem as AgentSetupProblem {
            return Self.agentSetupError(request, problem)
        } catch {
            return Self.agentSetupError(request, .invalid("CopyTrading couldn't make that change."))
        }
    }

    /// An approved apply of a setup that touches a live account. Returns nil once it took effect,
    /// or the code that says why not; a setup edited since the owner was asked is never applied.
    func applyApprovedAgentSetup(proposalID: String) async -> String? {
        guard let approved = agentSetupProposals.removeValue(forKey: proposalID) else { return "not_found" }
        guard approved.signature == setupDraft.signature else { return "setup_changed" }
        return await applySetupForAgent(start: approved.start).failureCode
    }

    /// What applying the draft would do to live accounts; the engine decides whether the owner
    /// must approve it.
    ///
    /// An account is known by the name it was saved under, so a rename is a new account to the
    /// Keychain and to these facts: a live account under a name that was never saved live is "made
    /// live", whatever was saved under that name before. A live account's limits, and which gurus
    /// copy into it, are its "changes". `agent-setup-apply-facts.json` holds the cases both this
    /// and the CLI's tests check.
    func agentApplyFacts(start: Bool = false) -> AgentSetupApplyFacts {
        let saved = savedTradingConfiguration
        let savedAccounts = Dictionary(
            (saved?.accounts ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let draft = try? setupDraft.submission().0
        func routes(into account: String, of configuration: TradingConfiguration?) -> [TradingRouteConfiguration] {
            (configuration?.routes ?? []).filter { $0.connections.contains { $0.accountID == account } }
                .sorted { $0.guruID < $1.guruID }
        }
        let restarts = [.checkAndRestart, .checkAndStart].contains(agentApplyPlan(start: start))
        var facts = AgentSetupApplyFacts()
        for account in setupDraft.accounts where account.environment == .live {
            let name = account.name.trimmed
            let origin = account.savedName.flatMap { savedAccounts[$0] }
            let madeLive = origin?.environment != .live || account.savedName != name
            if madeLive { facts.madeLive.append(name) }
            if !account.key.isEmpty || !account.secret.isEmpty { facts.newLiveKeys.append(name) }
            if !madeLive, let origin,
                origin.policy != account.policy
                    || routes(into: name, of: draft).map(\.guruID) != routes(into: origin.id, of: saved).map(\.guruID)
            {
                facts.changedLive.append(name)
            }
            if restarts { facts.startsLive.append(name) }
        }
        return facts
    }

    private enum AgentApplyPlan {
        /// Copying already runs the saved setup, and nothing changed.
        case unchanged
        /// Only limits changed while copying runs: they save the way the account sheet saves them.
        case limitsOnly
        /// Copying runs: every connection check, then save, and copying starts again as it was.
        case checkAndRestart
        /// Copying is paused: every connection check, then save, and copying stays paused.
        case checkAndSave
        /// Copying is paused or never started, and `--start` asks for it: Start Copying itself.
        case checkAndStart
    }

    private func agentApplyPlan(start: Bool) -> AgentApplyPlan {
        guard isCopyingSavedSetup else {
            if start { return .checkAndStart }
            return hasUnsavedSetupChanges || savedTradingConfiguration == nil ? .checkAndSave : .unchanged
        }
        if !hasUnsavedSetupChanges { return .unchanged }
        if draftHasOnlyLimitChanges { return .limitsOnly }
        return .checkAndRestart
    }

    /// Limits are all the draft changes, whoever changed them.
    private var draftHasOnlyLimitChanges: Bool {
        guard !setupDraft.hasTypedSecrets, let saved = savedTradingConfiguration,
            let edited = try? setupDraft.submission().0
        else { return false }
        return edited.limitOnlyChanges(from: saved) != nil
    }

    private func performAgentSetup(_ edit: AgentSetupRequest.Edit) async throws -> AgentSetupResult {
        guard isTradingUnlocked else { throw AgentSetupProblem.locked }
        switch edit {
        case .show:
            return .setup(agentSetupView())
        case .apply(let start):
            return .applied(await applySetupForAgent(start: start))
        default:
            break
        }
        guard !isValidatingTrading, !isActivatingTrading, !isApplyingChanges else { throw AgentSetupProblem.busy }
        var draft = setupDraft
        var imported: ImportedSetup?
        switch edit {
        case .show, .apply:
            break
        case .discord(let discord):
            if let ids = discord.channelIDs { draft.channels = ids.joined(separator: ", ") }
            if let ids = discord.authorIDs { draft.authors = ids.joined(separator: ", ") }
            if let token = discord.token { draft.discordToken = token.value }
        case .model(let model):
            try Self.edit(
                &draft, model: model, savedKeyFor: hasTradingSecrets ? savedTradingConfiguration?.provider.name : nil)
        case .account(let account):
            try Self.edit(&draft, account: account)
        case .guru(let guru):
            try Self.edit(&draft, guru: guru)
        case .alerts(let alerts):
            if let enabled = alerts.enabled { draft.notificationsEnabled = enabled }
            if let service = alerts.service, service != draft.notificationService {
                draft.notificationService = service
                // A token for one service never goes to the other.
                draft.notificationToken = ""
            }
            if let chatID = alerts.chatID { draft.notificationChatID = chatID }
            if let token = alerts.token { draft.notificationToken = token.value }
        case .importText(let text):
            if let saved = try Self.savedSetup(in: text.value) {
                let (filled, missing) = load(saved, into: &draft)
                imported = .saved(filled: filled, missing: missing)
                break
            }
            let setup = SetupImport(text: text.value)
            guard !setup.isEmpty else {
                throw AgentSetupProblem.invalid(
                    "Nothing in that file looks like a setup: no Discord, model, or Alpaca lines. Use labels such as “Discord token:” and “Alpaca API key:”."
                )
            }
            setup.apply(to: &draft)
            imported = .labels(setup)
        case .discard:
            discardSetupChanges()
            return .setup(agentSetupView())
        }
        let before = Dictionary(
            setupDraft.accounts.map { ($0.name.trimmed, $0.policy) }, uniquingKeysWith: { first, _ in first })
        for account in draft.accounts where before[account.name.trimmed] != account.policy {
            agentLimitEdits.insert(account.name.trimmed)
        }
        setupEditor = nil
        setupDraft = draft
        setupDraftDidChange()
        switch imported {
        case .labels(let setup):
            return .imported(AgentSetupImported(filled: setup.filled, missing: setup.missing, setup: agentSetupView()))
        case .saved(let filled, let missing):
            return .imported(AgentSetupImported(filled: filled, missing: missing, setup: agentSetupView()))
        case nil:
            break
        }
        return .setup(agentSetupView())
    }

    // Edits, each as Connections makes it.

    /// `savedKeyFor`: the service the saved model key belongs to, if any. A key only ever goes to
    /// the address it was given for: a new address needs its key in the same request.
    private static func edit(
        _ draft: inout ConnectionsDraft, model: AgentSetupRequest.Model, savedKeyFor: TradingProviderName?
    ) throws {
        if let service = model.service, service != draft.provider {
            draft.provider = service
            draft.modelName = SetupHelp.prefilledModel(for: service) ?? ""
            // A key typed for the last service never goes to this one.
            draft.providerAPIKey = ""
            if !service.acceptsBaseURL { draft.providerBaseURL = "" }
        }
        if let baseURL = model.baseURL {
            guard draft.provider.acceptsBaseURL || baseURL.isEmpty else {
                throw AgentSetupProblem.invalid(
                    "\(draft.provider.rawValue) is served at a fixed address. A base URL is only for ollama or openai_compatible.")
            }
            let keyWouldGo = !draft.providerAPIKey.isEmpty || savedKeyFor == draft.provider
            if baseURL.trimmed != draft.providerBaseURL.trimmed, keyWouldGo, model.key == nil {
                throw AgentSetupProblem.invalid(
                    "Changing where the model is served needs its key in the same request: add --secret-stdin or --from-file. A saved key is never sent to a new address."
                )
            }
            draft.providerBaseURL = baseURL
        }
        if let name = model.model { draft.modelName = name }
        if let key = model.key { draft.providerAPIKey = key.value }
    }

    private static func edit(_ draft: inout ConnectionsDraft, account edit: AgentSetupRequest.Account) throws {
        let name = edit.accountID
        let index = draft.accounts.firstIndex { $0.name.trimmed == name }
        switch edit.action {
        case .add:
            guard index == nil else {
                throw AgentSetupProblem.conflict(
                    "An account called \(name) is already in the setup. Change it with `copytrading setup account edit \(name)`.")
            }
            var account = TradingAccountDraft(name: name, environment: edit.environment ?? .paper)
            try apply(edit, to: &account)
            draft.accounts.append(account)
            // As Add Account does: the first guru that copies into nothing yet copies into it.
            if let route = draft.routes.firstIndex(where: { $0.connection == nil }) {
                draft.routes[route].connection = TradingConnectionDraft(accountID: name)
            }
        case .edit:
            guard let index else { throw missingAccount(name) }
            if let rename = edit.rename, rename != name {
                guard !draft.accounts.contains(where: { $0.name.trimmed == rename }) else {
                    throw AgentSetupProblem.conflict(
                        "\(name) can't be renamed \(rename): an account called \(rename) is already in the setup.")
                }
                draft.accounts[index].name = rename
                for route in draft.routes.indices where draft.routes[route].connection?.accountID.trimmed == name {
                    draft.routes[route].connection?.accountID = rename
                }
            }
            try apply(edit, to: &draft.accounts[index])
        case .remove:
            guard index != nil else { throw missingAccount(name) }
            draft.accounts.removeAll { $0.name.trimmed == name }
        }
    }

    private static func apply(_ edit: AgentSetupRequest.Account, to account: inout TradingAccountDraft) throws {
        if let environment = edit.environment { account.environment = environment }
        if let key = edit.key, let secret = edit.secret {
            account.key = key.value
            account.secret = secret.value
        }
        if let preference = edit.recoveryPreference { account.policy.recoveryPreference = preference }
        guard !edit.limits.isEmpty else { return }
        do {
            account.policy = try account.policy.applying(edit.limits)
        } catch TradingAccountPolicy.ChangeError.badValue(let field) {
            let kind =
                ["extended_hours", "overnight", "copy_exits", "approve_orders"].contains(field)
                ? "true or false" : "a number"
            throw AgentSetupProblem.invalid("\(account.name.trimmed): \(field) takes \(kind).")
        } catch {
            throw AgentSetupProblem.invalid("\(account.name.trimmed): one of the settings is not an account setting.")
        }
    }

    private static func missingAccount(_ name: String) -> AgentSetupProblem {
        .notFound(
            "There is no account called \(name) in the setup. Add it with `copytrading setup account add \(name)`, or see the names with `copytrading setup show`."
        )
    }

    private static func edit(_ draft: inout ConnectionsDraft, guru edit: AgentSetupRequest.Guru) throws {
        switch edit.action {
        case .add:
            try requireName(edit.guru)
            guard try guruIndex(edit.guru, in: draft) == nil else {
                throw AgentSetupProblem.conflict(
                    "A guru called \(edit.guru) is already in the setup. Change them with `copytrading setup guru edit \"\(edit.guru)\"`.")
            }
            var route = TradingRouteDraft(displayName: edit.guru)
            if edit.accountID == nil, let free = draft.accountChoices(for: route).first {
                // As Add Guru does: the first account no other guru copies into.
                route.connection = TradingConnectionDraft(accountID: free)
            }
            draft.routes.append(route)
            try apply(edit, toRouteAt: draft.routes.count - 1, in: &draft)
            try requireOwnChannel(routeAt: draft.routes.count - 1, in: draft)
        case .edit:
            guard let index = try guruIndex(edit.guru, in: draft) else { throw missingGuru(edit.guru) }
            if let rename = edit.rename, rename != draft.routes[index].displayName.trimmed {
                try requireName(rename)
                if let other = try guruIndex(rename, in: draft), other != index {
                    throw AgentSetupProblem.conflict(
                        "\(edit.guru) can't be renamed \(rename): a guru called \(rename) is already in the setup.")
                }
                draft.routes[index].displayName = rename
            }
            try apply(edit, toRouteAt: index, in: &draft)
            if edit.channelID != nil { try requireOwnChannel(routeAt: index, in: draft) }
        case .remove:
            guard let index = try guruIndex(edit.guru, in: draft) else { throw missingGuru(edit.guru) }
            draft.routes.remove(at: index)
        }
    }

    private static func apply(_ edit: AgentSetupRequest.Guru, toRouteAt index: Int, in draft: inout ConnectionsDraft) throws {
        let name = draft.routes[index].displayName.trimmed
        if let accountID = edit.accountID {
            guard draft.accountIDs.contains(accountID) else { throw missingAccount(accountID) }
            guard draft.accountChoices(for: draft.routes[index]).contains(accountID) else {
                let other = draft.routes.first { $0.connection?.accountID.trimmed == accountID }?.displayName.trimmed ?? ""
                throw AgentSetupProblem.conflict(
                    "\(accountID) already copies \(other), and each account copies one guru. Choose another account for \(name), or add one with `copytrading setup account add`."
                )
            }
            // As the guru sheet's account picker does: the guru's full position stays theirs.
            draft.routes[index].connection = TradingConnectionDraft(
                accountID: accountID, fullPositionUSD: draft.routes[index].connection?.fullPositionUSD ?? "")
        }
        if let channelID = edit.channelID { draft.routes[index].channelID = channelID }
        if let authorID = edit.authorID { draft.routes[index].authorID = authorID }
        if let playbook = edit.playbook { draft.routes[index].playbook = playbook }
        if let minutes = edit.repeatWindowMinutes {
            draft.routes[index].repeatWindowMinutes = minutes == 0 ? nil : minutes
        }
        if let full = edit.fullPositionUSD {
            guard draft.routes[index].connection != nil else {
                throw AgentSetupProblem.invalid(
                    "\(name) copies into no account yet, and a full position is what they hold in one. Give them one with --account."
                )
            }
            guard let amount = Decimal(string: full, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
                throw AgentSetupProblem.invalid("\(name)'s full position is a dollar amount above zero, such as 600.")
            }
            draft.routes[index].connection?.fullPositionUSD = full.trimmed
        }
    }

    /// A guru's ID comes from their channel (`GuruIdentity`), never from a request, so a name that
    /// reads as an ID would only hide another guru's.
    private static func requireName(_ name: String) throws {
        guard name.range(of: "^guru-[0-9a-f]{8}$", options: .regularExpression) != nil else { return }
        throw AgentSetupProblem.invalid(
            "\(name) reads as a guru ID, and a guru's ID comes from their channel. Give them a name instead.")
    }

    /// Each channel copies one guru: their channel names them, so two gurus can't read one.
    private static func requireOwnChannel(routeAt index: Int, in draft: ConnectionsDraft) throws {
        let channel = draft.effectiveChannel(for: draft.routes[index])
        guard !channel.isEmpty,
            let other = draft.routes.indices.first(where: {
                $0 != index && draft.effectiveChannel(for: draft.routes[$0]) == channel
            })
        else { return }
        let name = draft.routes[index].displayName.trimmed
        throw AgentSetupProblem.conflict(
            "\(draft.routes[other].displayName.trimmed) already reads channel \(channel), and each channel copies one guru. Give \(name) their own channel with --channel ID."
        )
    }

    /// The guru a request names: by the ID their channel gives them, else by name; two gurus with
    /// that name need the ID.
    private static func guruIndex(_ reference: String, in draft: ConnectionsDraft) throws -> Int? {
        if let index = draft.routes.firstIndex(where: { guruID(of: $0, in: draft) == reference }) { return index }
        let named = draft.routes.indices.filter {
            draft.routes[$0].displayName.trimmed.caseInsensitiveCompare(reference) == .orderedSame
        }
        guard named.count <= 1 else {
            let ids = named.compactMap { guruID(of: draft.routes[$0], in: draft) }.joined(separator: ", ")
            throw AgentSetupProblem.conflict("Two gurus are called \(reference). Name one by its ID: \(ids).")
        }
        return named.first
    }

    /// The ID a guru's channel gives them; nil until they have one.
    private static func guruID(of route: TradingRouteDraft, in draft: ConnectionsDraft) -> String? {
        draft.effectiveChannel(for: route).isEmpty ? nil : draft.guru(for: route)
    }

    private static func missingGuru(_ reference: String) -> AgentSetupProblem {
        .notFound(
            "There is no guru called \(reference) in the setup. See the names and IDs with `copytrading setup show`.")
    }

    // Import.

    /// What `setup import` read: Import Setup's labels, or a setup CopyTrading saved.
    private enum ImportedSetup {
        case labels(SetupImport)
        case saved(filled: [String], missing: [String])
    }

    /// A setup CopyTrading saved (its `trading-configuration.json`, or the `configuration` object in
    /// it), carried to this version by the same `SetupUpgrade` launch runs (ADR-0013); nil when the
    /// text isn't JSON, so it is read as Import Setup's labels. A setup no step reaches is refused
    /// by its version, and nothing is imported.
    private static func savedSetup(in text: String) throws -> TradingConfiguration? {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
            let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        let configuration = object["configuration"] as? [String: Any] ?? object
        let current = TradingConfiguration.currentVersion
        do {
            // The file has no account records, so every account waits for the owner after a
            // restart, the choice a setup saved before version 10 never held.
            return try SetupUpgrade.upgrade(configuration, facts: .init())
        } catch SetupUpgrade.Failure.tooOld(let version) {
            throw AgentSetupProblem.invalid(
                "That file is a setup saved at version \(version), from before CopyTrading could carry setups over (version \(SetupUpgrade.earliestVersion) and later). Nothing was imported. Set it up with `copytrading setup …`, or use Import Setup's label format."
            )
        } catch SetupUpgrade.Failure.tooNew(let version) {
            throw AgentSetupProblem.invalid(
                "That file is a setup saved at version \(version) by a newer CopyTrading; this one reads versions \(SetupUpgrade.earliestVersion) to \(current). Nothing was imported."
            )
        } catch {
            let version = (configuration["version"] as? Int).map { " (version \($0))" } ?? ""
            throw AgentSetupProblem.invalid(
                "That file looks like a saved setup\(version) but isn't one CopyTrading can read. Nothing was imported.")
        }
    }

    /// Fills the draft from a saved setup, as Import Setup fills it: every account comes in as
    /// paper, so a file never makes an account trade real money, and a key is never in the file.
    /// Returns what was filled and what the setup still needs, by name.
    private func load(_ saved: TradingConfiguration, into draft: inout ConnectionsDraft) -> ([String], [String]) {
        var file = ConnectionsDraft()
        file.load(saved)
        let savedHere = savedSetup()
        let savedNames = Set(savedTradingConfiguration?.accounts.map(\.id) ?? [])
        draft.channels = file.channels
        draft.authors = file.authors
        if draft.provider != file.provider || draft.providerBaseURL.trimmed != file.providerBaseURL.trimmed {
            // A key typed for one service or address never goes to another.
            draft.providerAPIKey = ""
        }
        draft.provider = file.provider
        draft.modelName = file.modelName
        draft.providerBaseURL = file.providerBaseURL
        let typed = Dictionary(
            draft.accounts.map { ($0.name.trimmed, ($0.key, $0.secret)) }, uniquingKeysWith: { first, _ in first })
        draft.accounts = file.accounts.map { account in
            var paper = TradingAccountDraft(
                name: account.name, environment: .paper, policy: account.policy,
                savedName: savedNames.contains(account.name) ? account.name : nil)
            if let keys = typed[account.name] { (paper.key, paper.secret) = keys }
            return paper
        }
        draft.routes = file.routes
        if draft.notificationService != file.notificationService { draft.notificationToken = "" }
        draft.notificationsEnabled = file.notificationsEnabled
        draft.notificationService = file.notificationService
        draft.notificationChatID = file.notificationChatID

        var filled = ["Discord channels", "\(draft.provider.rawValue) model \(draft.modelName)"]
        filled += draft.accounts.map { account in
            let restart = account.policy.recoveryPreference == .manual ? "Wait for me" : "Carry on by itself"
            return "account \(account.name) (paper; after a restart \(restart))"
        }
        filled += draft.routes.map { "guru \($0.displayName.trimmed)" }
        if draft.notificationsEnabled { filled.append("\(draft.notificationService.rawValue) alerts") }
        var missing: [String] = []
        if draft.discordToken.isEmpty, savedHere?.secrets.discordToken.isEmpty != false { missing.append("Discord token") }
        let savedModelKey =
            savedHere?.configuration.provider.name == draft.provider && savedHere?.secrets.providerAPIKey.isEmpty == false
        if draft.provider.requiresAPIKey, draft.providerAPIKey.isEmpty, !savedModelKey {
            missing.append("\(draft.provider.rawValue) API key")
        }
        for account in draft.accounts where account.key.isEmpty || account.secret.isEmpty {
            let keys = savedHere?.secrets.brokers.contains { $0.accountID == account.name && !$0.key.isEmpty } == true
            if !keys { missing.append("Alpaca keys for \(account.name)") }
        }
        let savedToken =
            savedHere?.configuration.notification?.service == draft.notificationService
            && savedHere?.secrets.notificationToken?.isEmpty == false
        if draft.notificationsEnabled, draft.notificationToken.isEmpty, !savedToken {
            missing.append("\(draft.notificationService.rawValue) alert token")
        }
        return (filled, missing)
    }

    // Apply: Start Copying, waited for.

    /// Every connection check, then save, waited for. Copying that runs starts again with the
    /// setup (limits alone save the way the account sheet saves them); copying that is paused stays
    /// paused unless `start` asks for Start Copying itself, a first setup included.
    func applySetupForAgent(start: Bool = false) async -> AgentSetupApplied {
        guard isTradingUnlocked else { return AgentSetupApplied(status: .failed, message: AgentSetupProblem.locked.message) }
        guard !isBusyForAgentApply else {
            return AgentSetupApplied(status: .failed, message: AgentSetupProblem.busy.message)
        }
        await settlePendingStart()
        // The owner may have started something in the window while the start settled.
        guard !isBusyForAgentApply else {
            return AgentSetupApplied(status: .failed, message: AgentSetupProblem.busy.message)
        }
        guard !hasPendingActivation else { return Self.startSettling }
        let plan = agentApplyPlan(start: start)
        switch plan {
        case .unchanged:
            return AgentSetupApplied(
                status: .unchanged, message: isCopyingSavedSetup ? nil : "Copying stays paused, as you left it.")
        case .limitsOnly:
            let saved = await saveLimitOnlyChanges(for: nil)
            if saved == true, limitsAwaitingStart { return Self.startSettling }
            return saved == true
                ? AgentSetupApplied(status: .applied, message: nil)
                : AgentSetupApplied(status: .failed, message: message ?? "The new limits weren't saved. Try again.")
        case .checkAndRestart, .checkAndSave, .checkAndStart:
            break
        }
        if let missing = missingBeforeCheck {
            return AgentSetupApplied(status: .failed, message: missing)
        }
        if let moved = modelAddressMovedWithoutKey {
            return AgentSetupApplied(status: .failed, message: moved)
        }
        if plan == .checkAndSave {
            return await checkAndSaveForAgent()
        }
        guard canCheckAndStart else {
            return AgentSetupApplied(
                status: .failed, message: "Copying is starting or stopping. Wait a moment, then apply again.")
        }
        latestSetupChecks = []
        guard let work = checkAndStartCopying() else {
            return AgentSetupApplied(status: .failed, message: message ?? "The setup couldn't be checked.")
        }
        await work.value
        await settlePendingStart()
        let checks = latestSetupChecks.map(agentCheck)
        if checks.contains(where: { $0.state == .failed }) {
            return AgentSetupApplied(
                status: .failedChecks, message: "Some connections need attention. Nothing was saved.", checks: checks)
        }
        let copying = [.running, .starting, .degraded].contains(tradingStatus?.state)
        if copying, savedTradingConfiguration != nil, !hasUnsavedSetupChanges {
            let said = plan == .checkAndStart ? "Saved, and copying started." : message
            return AgentSetupApplied(status: .applied, message: said, checks: checks)
        }
        if isConfirmingActivation {
            return AgentSetupApplied(
                status: .failed,
                message: "Copying is starting the new setup but hasn't confirmed it yet. Run `copytrading setup show` in a moment.",
                checks: checks)
        }
        return AgentSetupApplied(
            status: .failed, message: message ?? "Copying didn't start. Open CopyTrading to see why.", checks: checks)
    }

    private var isBusyForAgentApply: Bool {
        isValidatingTrading || isActivatingTrading || isTradingCommandPending || isApplyingChanges
    }

    /// A start the engine took but has not committed yet settles within seconds. Apply waits for it,
    /// asking the engine the way the status refresh does, so a setup that is being started is never
    /// reported as not applied, and an apply right after another one is not refused.
    private func settlePendingStart() async {
        guard let starter = tradingControl else { return }
        let clock = ContinuousClock()
        let deadline = clock.now + startSettleLimit
        while hasPendingActivation, clock.now < deadline {
            await reconcilePendingTradingActivation(using: starter)
            guard hasPendingActivation else { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private static let startSettling = AgentSetupApplied(
        status: .failed,
        message:
            "A start is still settling, so nothing was applied. Run `copytrading setup apply` again in a moment."
    )

    /// Copying is paused: check every connection, then save without starting. Copying stays as
    /// the owner left it; the next Start Copying checks the saved setup again and starts it.
    private func checkAndSaveForAgent() async -> AgentSetupApplied {
        guard tradingStatus?.state == .paused, !isTradingCommandPending else {
            return AgentSetupApplied(
                status: .failed, message: "Copying is starting or stopping. Wait a moment, then apply again.")
        }
        let submission: (TradingConfiguration, TradingSecrets)
        do {
            submission = try setupDraft.submission()
        } catch {
            return AgentSetupApplied(status: .failed, message: Self.setupProblem(for: error))
        }
        latestSetupChecks = []
        checkedSetupSignature = setupDraft.signature
        let passed = await validateTradingSettings(submission.0, enteredSecrets: submission.1)
        let checks = latestSetupChecks.map(agentCheck)
        if checks.contains(where: { $0.state == .failed }) {
            return AgentSetupApplied(
                status: .failedChecks, message: "Some connections need attention. Nothing was saved.", checks: checks)
        }
        guard passed, saveCheckedSetupWithoutStarting() else {
            return AgentSetupApplied(
                status: .failed, message: message ?? "The setup wasn't saved. Try again.", checks: checks)
        }
        return AgentSetupApplied(status: .applied, message: "Saved. Copying stays paused, as you left it.", checks: checks)
    }

    /// The model would be served somewhere new with the key saved for somewhere else.
    private var modelAddressMovedWithoutKey: String? {
        guard let saved = savedTradingConfiguration, hasTradingSecrets, setupDraft.providerAPIKey.isEmpty,
            saved.provider.name == setupDraft.provider,
            (saved.provider.baseURL ?? "") != (setupDraft.providerConfiguration.baseURL ?? "")
        else { return nil }
        return
            "The model's address changed from the saved one, and its saved key is never sent to a new address. Give the key with `copytrading setup model --secret-stdin`."
    }

    /// What the setup still needs before it can be checked: each account or guru by name, and
    /// the exact command that fills it in.
    private var missingBeforeCheck: String? {
        guard !isFilledInToCheck else { return nil }
        let draft = setupDraft
        let savedKeys = savedSetup()?.secrets
        var needs: [String] = []
        if draft.sourceChannelIDs.isEmpty {
            needs.append("Discord has no channel: `copytrading setup discord --channels ID`")
        }
        if draft.discordToken.isEmpty && savedKeys?.discordToken.isEmpty != false {
            needs.append("Discord has no token: `copytrading setup discord --secret-stdin`")
        }
        if draft.modelName.trimmed.isEmpty {
            needs.append("the model has no name: `copytrading setup model --model NAME`")
        }
        if !interpreterHasKey {
            needs.append("\(draft.provider.rawValue) has no API key: `copytrading setup model --secret-stdin`")
        }
        if let problem = draft.providerConfiguration.baseURLProblem {
            needs.append("\(problem) (`copytrading setup model --base-url URL --secret-stdin`)")
        }
        if draft.accounts.isEmpty {
            needs.append("there is no Alpaca account: `copytrading setup account add NAME --secret-stdin`")
        }
        for account in draft.accounts {
            let name = account.name.trimmed
            let saved = savedKeys?.brokers.contains { $0.accountID == name && !$0.key.isEmpty } == true
            guard account.key.isEmpty || account.secret.isEmpty, !saved else { continue }
            let renamed =
                account.savedName.map { $0 != name ? " (renamed from \($0), whose keys stay with that name)" : "" } ?? ""
            needs.append("\(name) has no Alpaca keys\(renamed): `copytrading setup account edit \(name) --secret-stdin`")
        }
        if draft.routes.isEmpty {
            needs.append("there is no guru: `copytrading setup guru add NAME --account ACCOUNT`")
        }
        let accountIDs = Set(draft.accountIDs)
        for route in draft.routes {
            let name = route.displayName.trimmed.isEmpty ? (Self.guruID(of: route, in: draft) ?? "a guru") : route.displayName.trimmed
            if route.connection.map({ accountIDs.contains($0.accountID.trimmed) }) != true {
                needs.append("\(name) copies into no account: `copytrading setup guru edit \"\(name)\" --account ACCOUNT`")
            }
            if draft.effectiveChannel(for: route).isEmpty {
                needs.append("\(name) has no channel: `copytrading setup guru edit \"\(name)\" --channel ID`")
            }
        }
        if needs.isEmpty {
            needs.append("a connection isn't filled in yet: see `copytrading setup show`")
        }
        return "The setup isn't ready to check, so nothing was saved: " + needs.joined(separator: "; ") + "."
    }

    // The setup as Connections shows it.

    func agentSetupView() -> AgentSetupView {
        let draft = setupDraft
        let saved = savedSetup()
        func state(typed: Bool, saved isSaved: Bool) -> AgentKeyState {
            typed ? .entered : isSaved ? .saved : .missing
        }
        let savedModelKey =
            saved?.configuration.provider.name == draft.provider && saved?.secrets.providerAPIKey.isEmpty == false
        let modelKey =
            !draft.providerAPIKey.isEmpty
            ? AgentKeyState.entered
            : savedModelKey ? .saved : draft.provider.requiresAPIKey ? .missing : .notNeeded
        let savedAlertToken =
            saved?.configuration.notification?.service == draft.notificationService
            && saved?.secrets.notificationToken?.isEmpty == false
        return AgentSetupView(
            saved: savedTradingConfiguration != nil,
            unsavedChanges: hasUnsavedSetupChanges,
            copying: Self.code(of: CopyingState.overall(self).word),
            discord: .init(
                channelIDs: draft.sourceChannelIDs, authorIDs: ConnectionsDraft.split(draft.authors),
                token: state(typed: !draft.discordToken.isEmpty, saved: saved?.secrets.discordToken.isEmpty == false),
                check: connectionCheckResult(.discord)?.check.map(agentCheck)),
            model: .init(
                service: draft.provider.rawValue, model: draft.modelName.trimmed,
                baseURL: draft.providerConfiguration.baseURL, key: modelKey,
                check: connectionCheckResult(.interpreter)?.check.map(agentCheck)),
            accounts: draft.accounts.map { account in
                let name = account.name.trimmed
                let savedKeys = saved?.secrets.brokers.contains { $0.accountID == name && !$0.key.isEmpty } == true
                return .init(
                    accountID: name, environment: account.environment,
                    keys: state(typed: !account.key.isEmpty || !account.secret.isEmpty, saved: savedKeys),
                    limits: Self.limitOrder.compactMap { field in
                        account.policy.text(of: field).map { AgentLimitChange(field: field, value: $0) }
                    },
                    recoveryPreference: account.policy.recoveryPreference,
                    check: connectionCheckResult(.account(name))?.check.map(agentCheck))
            },
            gurus: draft.routes.map { route in
                .init(
                    guruID: Self.guruID(of: route, in: draft), name: route.displayName.trimmed,
                    channelID: draft.effectiveChannel(for: route).nilIfEmpty,
                    authorID: route.authorID.trimmed.nilIfEmpty,
                    accountID: route.connection?.accountID.trimmed.nilIfEmpty,
                    fullPositionUSD: route.connection.map { draft.fullPosition(for: $0) }?.nilIfEmpty,
                    repeatWindowMinutes: route.repeatWindowMinutes,
                    playbookCharacters: route.playbook.count)
            },
            alerts: .init(
                enabled: draft.notificationsEnabled, service: draft.notificationService,
                chatID: draft.notificationChatID.trimmed.nilIfEmpty,
                token: state(typed: !draft.notificationToken.isEmpty, saved: savedAlertToken),
                check: connectionCheckResult(.alerts)?.check.map(agentCheck)))
    }

    /// A copying word as the contract spells it, the same code `copytrading status` shows.
    private static func code(of word: CopyingState.Word) -> String {
        switch word {
        case .copying: "copying"
        case .sellsOnly: "sells_only"
        case .paused: "paused"
        case .stopped: "stopped"
        case .notStarted: "not_started"
        }
    }

    /// The account settings in the account sheet's order.
    private static let limitOrder = [
        "max_order_usd", "max_symbol_usd", "max_total_usd", "daily_loss_cap_usd", "max_entries_per_day",
        "max_signal_age_seconds", "order_timeout_seconds", "poll_seconds", "extended_hours", "overnight",
        "copy_exits", "approve_orders", "max_above_signal_pct", "max_below_signal_pct",
    ]

    /// A check as its row in Connections reads it: a failure says who, what happened, and what to do.
    func agentCheck(_ check: TradingCapabilityCheck) -> AgentSetupCheck {
        let connection: AgentSetupCheck.Connection =
            switch check.name {
            case .source: .discord
            case .model: .model
            case .broker: .account
            case .notification: .alerts
            case .configuration: .setup
            }
        let state: AgentSetupCheck.State =
            switch check.state {
            case .ready: .passed
            case .failed: .failed
            case .notConfigured: .notConfigured
            }
        let message =
            state == .failed
            ? "\(CapabilityCheckTitle.text(for: check)): \(ConnectionProblem.text(for: check, modelName: setupDraft.modelName))"
            : nil
        return AgentSetupCheck(
            connection: connection, subject: check.subject, state: state, reason: check.reasonCode, message: message)
    }

    private static func agentSetupError(_ request: AgentSetupRequest, _ problem: AgentSetupProblem) -> String {
        AgentSetupResponse.errorLine(requestID: request.requestID, code: problem.code, message: problem.message)
    }

    private static func proposalID(in line: String) -> String? {
        struct Answer: Decodable {
            struct Proposal: Decodable {
                let type: String
                let proposalID: String

                enum CodingKeys: String, CodingKey {
                    case type
                    case proposalID = "proposal_id"
                }
            }

            let ok: Proposal?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: Data(line.utf8)), answer.ok?.type == "proposal"
        else { return nil }
        return answer.ok?.proposalID
    }
}
