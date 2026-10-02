import DesktopCore

/// The engine's approval queue: what an agent or the assistant asked for, and the owner's decision.
protocol AgentProposalOperations: Sendable {
    func agentProposals() async throws -> [AgentProposal]
    func approveProposal(id: String, digest: String) async throws -> AgentProposal
    func rejectProposal(id: String) async throws -> AgentProposal
    func discardProposals() async throws -> Int
}

extension EngineActions: AgentProposalOperations {}
