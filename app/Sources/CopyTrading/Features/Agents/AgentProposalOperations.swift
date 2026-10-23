import DesktopCore

/// The engine's approval queue: what an agent or the assistant asked for, and the owner's decision.
protocol AgentProposalOperations: Sendable {
    func agentProposals() async throws -> [AgentProposal]
    func approveProposal(id: String, digest: String) async throws -> AgentProposal
    func completeProposal(id: String, succeeded: Bool, code: String?) async throws -> AgentProposal
    func rejectProposal(id: String) async throws -> AgentProposal
    func discardProposals() async throws -> Int
    /// Whether a setup request the app answers itself may run; its keys never travel with it.
    func authorizeSetup(
        _ setup: AgentSetupAuthorizationRequest, context: AgentRequestContext
    ) async throws -> AgentSetupAuthorization
}

extension EngineActions: AgentProposalOperations {}
