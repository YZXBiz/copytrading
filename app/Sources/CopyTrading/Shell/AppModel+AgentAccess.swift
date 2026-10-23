import DesktopCore
import Foundation

extension AppModel {
    /// Whether a request touches a paper or a live account, so the sheet can say which.
    func environment(of proposal: AgentProposal) -> TradingEnvironment? {
        if let environment = proposal.environment { return environment }
        if case .applySetup = proposal.subject { return .live }
        guard let accountID = proposal.accountID else { return nil }
        return savedTradingConfiguration?.accounts.first { $0.id == accountID }?.environment
    }

    /// What a limits request would change: each setting, its value now, and the value after.
    func limitRows(of proposal: AgentProposal) -> [(title: String, now: String, after: String)] {
        guard case .setAccountLimits(let accountID, let changes) = proposal.subject else { return [] }
        let current = savedTradingConfiguration?.accounts.first { $0.id == accountID }?.policy
        return changes.map { change in
            (
                AgentProposal.limitTitle(change.field),
                current?.text(of: change.field).map { AgentProposal.limitValue(change.field, $0) } ?? "—",
                AgentProposal.limitValue(change.field, change.value)
            )
        }
    }

    /// What applying a setup does to live accounts, one row each: the accounts it makes live,
    /// gives new keys, changes, and starts copying into.
    func setupRows(of proposal: AgentProposal) -> [(title: String, value: String)] {
        guard case .applySetup(let facts) = proposal.subject else { return [] }
        return [
            (L10n.string("Becomes live"), facts.madeLive),
            (L10n.string("New keys"), facts.newLiveKeys),
            (L10n.string("Limits change"), facts.changedLive),
            (L10n.string("Copies into"), facts.startsLive),
        ].filter { !$0.1.isEmpty }.map { ($0.0, L10n.list($0.1)) }
    }

    /// The oldest proposal still waiting for the owner; it drives the approval sheet.
    var pendingAgentProposal: AgentProposal? {
        agentProposals.first { $0.state == .pending }
    }

    func loadAgentAccess(stateRoot: URL) {
        let store = AgentAccessStore(stateRoot: stateRoot)
        agentAccessStore = store
        do {
            let choice = try store.load()
            agentAccess = choice.access
            agentSetupChanges = choice.setupChanges
        } catch {
            agentAccess = .off
            agentSetupChanges = false
            agentAccessMessage = L10n.string("%@ Agent access stays off until you choose again.", Self.userMessage(for: error))
        }
    }

    /// Listen for the `copytrading` CLI and MCP server when the owner allowed agents.
    func startAgentRelay(stateRoot: URL, actions: EngineActions) {
        stopAgentRelay()
        guard let level = agentAccess.accessLevel else { return }
        let relay = AgentRelay(
            socketURL: AgentRelay.socketURL(stateRoot: stateRoot),
            accessLevel: level,
            setupChanges: agentSetupChanges,
            isUnlocked: { [weak self] in await self?.isTradingUnlocked ?? false },
            send: { line, context in try await actions.control(line: line, context: context) },
            setup: { [weak self] line, context in
                guard let self else {
                    return AgentSetupResponse.errorLine(
                        requestID: "", code: "unavailable", message: AgentSetupProblem.engineNotRunning.message)
                }
                return await self.answerAgentSetup(line: line, context: context)
            }
        )
        do {
            try relay.start()
            agentRelay = relay
            isAgentRelayListening = true
        } catch {
            agentAccessMessage = L10n.string("Agents cannot connect: %@", Self.userMessage(for: error))
        }
    }

    func stopAgentRelay() {
        agentRelay?.stop()
        agentRelay = nil
        isAgentRelayListening = false
        agentProposals = []
    }

    /// Change who may use the CLI and MCP server; every change needs the owner.
    func setAgentAccess(_ access: AgentAccessSetting) async {
        guard access != agentAccess, let store = agentAccessStore, !isChangingAgentAccess else { return }
        isChangingAgentAccess = true
        defer { isChangingAgentAccess = false }
        do {
            try await confirmOwner(L10n.string(access == .off ? "Turn off agent access" : "Allow agents to use CopyTrading"))
            try store.save(AgentAccessChoice(access: access, setupChanges: agentSetupChanges))
        } catch {
            agentAccessMessage = Self.userMessage(for: error)
            return
        }
        agentAccess = access
        agentAccessMessage = nil
        await restartAgentRelay(store: store)
    }

    /// "Allow setup changes from the command line": lets `copytrading setup` change the setup.
    /// Off by default; turning it on or off needs the owner, like every access change.
    func setAgentSetupChanges(_ allowed: Bool) async {
        guard allowed != agentSetupChanges, let store = agentAccessStore, !isChangingAgentAccess else { return }
        isChangingAgentAccess = true
        defer { isChangingAgentAccess = false }
        do {
            try await confirmOwner(
                L10n.string(
                    allowed ? "Allow setup changes from the command line" : "Turn off setup changes from the command line"))
            try store.save(AgentAccessChoice(access: agentAccess, setupChanges: allowed))
        } catch {
            agentAccessMessage = Self.userMessage(for: error)
            return
        }
        agentSetupChanges = allowed
        agentAccessMessage = nil
        await restartAgentRelay(store: store)
    }

    /// The relay carries the owner's choices into every request, so a change starts it again.
    private func restartAgentRelay(store: AgentAccessStore) async {
        if let actions = agentEngineActions() {
            if agentRelay != nil { _ = try? await actions.discardProposals() }
            startAgentRelay(stateRoot: store.url.deletingLastPathComponent(), actions: actions)
        }
        await refreshAgentActivity()
    }

    func refreshAgentActivity() async {
        if isAgentRelayListening || isTradingUnlocked { await refreshAssistantProposals() }
        if isTradingUnlocked, let actions = agentEngineActions() {
            agentAudit = (try? await actions.agentAudit(limit: 20)) ?? agentAudit
        }
    }

    /// Load the proposals waiting for the owner whether or not agent access is on, so one the
    /// assistant made opens the approval sheet.
    func refreshAssistantProposals() async {
        guard let operations = agentProposalOperations() else { return }
        agentProposals = (try? await operations.agentProposals()) ?? agentProposals
        for proposal in agentProposals
        where proposal.state == .pending && !AgentCallerName.isAssistant(proposal.requestedBy.path)
            && announcedProposalIDs.insert(proposal.id).inserted
        {
            announceAgentRequest(proposal)
        }
    }

    /// Perform what an agent asked for, after a fresh Touch ID or password check.
    func approveAgentProposal(_ proposal: AgentProposal) async {
        guard let operations = agentProposalOperations() else { return }
        do {
            try await confirmOwner(L10n.string("Approve: %@", proposal.summary))
            let result = try await operations.approveProposal(id: proposal.id, digest: proposal.digest)
            if result.state == .running, case .setAccountLimits(let accountID, let changes) = result.subject {
                // Only the app can change its saved setup: do it, then tell the engine how it went.
                let failure = await applyAgentLimitChanges(accountID: accountID, changes: changes)
                let done = try await operations.completeProposal(
                    id: result.id, succeeded: failure == nil, code: failure)
                agentAccessMessage = done.resultMessage
            } else if result.state == .running, case .setRecovery(let accountID, let preference) = result.subject {
                let failure = await applyAgentRecovery(accountID: accountID, preference: preference)
                let done = try await operations.completeProposal(
                    id: result.id, succeeded: failure == nil, code: failure)
                agentAccessMessage = done.resultMessage
            } else if result.state == .running, case .startProcessing = result.subject {
                let failure = await startCopyingForAgent()
                let done = try await operations.completeProposal(
                    id: result.id, succeeded: failure == nil, code: failure)
                agentAccessMessage = done.resultMessage
            } else if result.state == .running, case .applySetup = result.subject {
                // Start Copying on the setup the owner was shown; live accounts ask for Touch ID again.
                let failure = await applyApprovedAgentSetup(proposalID: result.id)
                let done = try await operations.completeProposal(
                    id: result.id, succeeded: failure == nil, code: failure)
                agentAccessMessage = done.resultMessage
            } else {
                agentAccessMessage = result.resultMessage
            }
        } catch {
            agentAccessMessage = Self.userMessage(for: error)
        }
        await refreshAgentActivity()
    }

    func rejectAgentProposal(_ proposal: AgentProposal) async {
        guard let operations = agentProposalOperations() else { return }
        do {
            _ = try await operations.rejectProposal(id: proposal.id)
            agentAccessMessage = nil
        } catch {
            agentAccessMessage = Self.userMessage(for: error)
        }
        await refreshAgentActivity()
    }
}
