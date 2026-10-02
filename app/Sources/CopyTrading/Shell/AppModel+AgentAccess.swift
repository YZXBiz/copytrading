import DesktopCore
import Foundation

extension AppModel {
    /// The oldest proposal still waiting for the owner; it drives the approval sheet.
    var pendingAgentProposal: AgentProposal? {
        agentProposals.first { $0.state == .pending }
    }

    func loadAgentAccess(stateRoot: URL) {
        let store = AgentAccessStore(stateRoot: stateRoot)
        agentAccessStore = store
        do {
            agentAccess = try store.load()
        } catch {
            agentAccess = .off
            agentAccessMessage = L10n.string("%@ Agent access stays off until you choose again.", error.localizedDescription)
        }
    }

    /// Listen for the `copytrading` CLI and MCP server when the owner allowed agents.
    func startAgentRelay(stateRoot: URL, actions: EngineActions) {
        stopAgentRelay()
        guard let level = agentAccess.accessLevel else { return }
        let relay = AgentRelay(
            socketURL: AgentRelay.socketURL(stateRoot: stateRoot),
            accessLevel: level,
            isUnlocked: { [weak self] in await self?.isTradingUnlocked ?? false },
            send: { line, context in try await actions.control(line: line, context: context) }
        )
        do {
            try relay.start()
            agentRelay = relay
            isAgentRelayListening = true
        } catch {
            agentAccessMessage = L10n.string("Agents cannot connect: %@", error.localizedDescription)
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
            try store.save(access)
        } catch {
            agentAccessMessage = error.localizedDescription
            return
        }
        agentAccess = access
        agentAccessMessage = nil
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
    }

    /// Perform what an agent asked for, after a fresh Touch ID or password check.
    func approveAgentProposal(_ proposal: AgentProposal) async {
        guard let operations = agentProposalOperations() else { return }
        do {
            try await confirmOwner(L10n.string("Approve: %@", proposal.summary))
            let result = try await operations.approveProposal(id: proposal.id, digest: proposal.digest)
            agentAccessMessage = result.resultMessage
        } catch {
            agentAccessMessage = error.localizedDescription
        }
        await refreshAgentActivity()
    }

    func rejectAgentProposal(_ proposal: AgentProposal) async {
        guard let operations = agentProposalOperations() else { return }
        do {
            _ = try await operations.rejectProposal(id: proposal.id)
            agentAccessMessage = nil
        } catch {
            agentAccessMessage = error.localizedDescription
        }
        await refreshAgentActivity()
    }
}
