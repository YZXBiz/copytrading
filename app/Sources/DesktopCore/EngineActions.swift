import Foundation

/// Resolves the current IPC client for each model action, including after an owned child restart.
public struct EngineActions: Sendable {
    private let supervisor: ProcessSupervisor

    public init(supervisor: ProcessSupervisor) {
        self.supervisor = supervisor
    }

    public func status() async throws -> EngineStatus {
        let client = try await supervisor.engineClient()
        return try await client.status()
    }

    public func tradingStatus() async throws -> TradingStatus {
        let client = try await supervisor.engineClient()
        return try await client.tradingStatus()
    }

    public func tradingActivation(activationID: String) async throws -> TradingActivationStatus {
        let client = try await supervisor.engineClient()
        return try await client.tradingActivation(activationID: activationID)
    }

    public func validateTrading(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws -> TradingValidation {
        let client = try await supervisor.engineClient()
        return try await client.validateTrading(configuration: configuration, secrets: secrets)
    }

    public func checkConnection(_ connection: TradingConnectionCheck) async throws -> TradingCapabilityCheck {
        let client = try await supervisor.engineClient()
        return try await client.checkConnection(connection)
    }

    public func startTrading(
        configuration: TradingConfiguration,
        secrets: TradingSecrets,
        validationToken: String,
        activationID: String
    ) async throws -> TradingStatus {
        let client = try await supervisor.engineClient()
        return try await client.startTrading(
            configuration: configuration,
            secrets: secrets,
            validationToken: validationToken,
            activationID: activationID
        )
    }

    public func pauseTrading() async throws -> TradingStatus {
        let client = try await supervisor.engineClient()
        return try await client.pauseTrading()
    }

    public func updateAccountLimits(configuration: TradingConfiguration) async throws -> String {
        let client = try await supervisor.engineClient()
        return try await client.updateAccountLimits(configuration: configuration)
    }

    public func createBackup(destination: URL) async throws -> BackupManifestView {
        let client = try await supervisor.engineClient()
        return try await client.createBackup(destination: destination)
    }

    public func previewRestore(archive: URL) async throws -> RestorePreviewView {
        let client = try await supervisor.engineClient()
        return try await client.previewRestore(archive: archive)
    }

    public func prepareRestoreCandidate(stagingID: String) async throws -> String {
        let client = try await supervisor.engineClient()
        return try await client.prepareRestoreCandidate(stagingID: stagingID)
    }

    public func restoreCandidateStatus() async throws -> PendingRestoreCandidateView? {
        let client = try await supervisor.engineClient()
        return try await client.restoreCandidateStatus()
    }

    public func abortRestoreCandidate(candidateID: String) async throws {
        let client = try await supervisor.engineClient()
        try await client.abortRestoreCandidate(candidateID: candidateID)
    }

    public func restorePreflight(
        candidateID: String, accounts: [RestorePreflightAccount]
    ) async throws -> RestorePreflightView {
        let client = try await supervisor.engineClient()
        return try await client.restorePreflight(candidateID: candidateID, accounts: accounts)
    }

    public func completeRestoreCandidate(
        candidateID: String, completionToken: String
    ) async throws {
        let client = try await supervisor.engineClient()
        try await client.completeRestoreCandidate(
            candidateID: candidateID,
            completionToken: completionToken
        )
    }

    public func controlAccount(_ command: AccountControlCommand) async throws -> AccountControlResult {
        let client = try await supervisor.engineClient()
        return try await client.controlAccount(command)
    }

    public func resolveOwnership(
        accountID: String, resolution: OwnershipResolutionRequest
    ) async throws -> OwnershipResolution {
        let client = try await supervisor.engineClient()
        return try await client.resolveOwnership(accountID: accountID, resolution: resolution)
    }

    public func accounts(
        beforeAccountID: String? = nil, limit: Int = 50
    ) async throws -> AccountOverviewPage {
        let client = try await supervisor.engineClient()
        return try await client.accounts(beforeAccountID: beforeAccountID, limit: limit)
    }

    public func sourceActivity(beforeSeq: Int? = nil, limit: Int = 50) async throws -> SourceActivityPage {
        let client = try await supervisor.engineClient()
        return try await client.sourceActivity(beforeSeq: beforeSeq, limit: limit)
    }

    public func evaluateHistoricalProfile(
        _ evaluation: HistoricalProfileEvaluationRequest
    ) async throws -> ProfileEvaluation {
        let client = try await supervisor.engineClient()
        return try await client.evaluateHistoricalProfile(evaluation)
    }

    public func reviewProfileExamples(
        _ request: ProfileExampleReviewRequest
    ) async throws -> ProfileExampleReview {
        let client = try await supervisor.engineClient()
        return try await client.reviewProfileExamples(request)
    }

    public func learnGuruPlaybook(
        _ learning: GuruPlaybookLearningRequest
    ) async throws -> LearnedGuruPlaybook {
        let client = try await supervisor.engineClient()
        return try await client.learnGuruPlaybook(learning)
    }

    public func replayGuruPosts(_ replay: GuruReplayRequest) async throws -> GuruReplay {
        let client = try await supervisor.engineClient()
        return try await client.replayGuruPosts(replay)
    }

    public func accountFeed(
        accountID: String, beforeSeq: Int? = nil, limit: Int = 50
    ) async throws -> AccountFeedPage {
        let client = try await supervisor.engineClient()
        return try await client.accountFeed(accountID: accountID, beforeSeq: beforeSeq, limit: limit)
    }

    public func equityHistory(
        accountID: String, window: EquityHistoryWindow
    ) async throws -> EquityHistory? {
        let client = try await supervisor.engineClient()
        return try await client.equityHistory(accountID: accountID, window: window)
    }

    public func saveManualCorrection(
        _ correction: ManualCorrectionRequest
    ) async throws -> ManualCorrectionOutcome {
        let client = try await supervisor.engineClient()
        return try await client.saveManualCorrection(correction)
    }

    public func previewManualOrder(
        _ preview: ManualPreviewRequest
    ) async throws -> ManualOrderPreview {
        let client = try await supervisor.engineClient()
        return try await client.previewManualOrder(preview)
    }

    public func previewLotSale(_ preview: LotSalePreviewRequest) async throws -> LotSalePreview {
        let client = try await supervisor.engineClient()
        return try await client.previewLotSale(preview)
    }

    public func confirmLotSale(_ sale: LotSaleConfirmation) async throws -> LotSaleResult {
        let client = try await supervisor.engineClient()
        return try await client.confirmLotSale(sale)
    }

    public func confirmManualOrders(
        _ commands: [ManualConfirmationRequest]
    ) async throws -> ManualCommandsOutcome {
        let client = try await supervisor.engineClient()
        return try await client.confirmManualOrders(commands)
    }

    public func manualCommandResult(
        accountID: String, commandID: String
    ) async throws -> ManualCommandResult {
        let client = try await supervisor.engineClient()
        return try await client.manualCommandResult(accountID: accountID, commandID: commandID)
    }

    public func manualCommandPage(
        accountID: String, sourceID: String, beforeCommandID: String? = nil, limit: Int = 50
    ) async throws -> ManualCommandPage {
        let client = try await supervisor.engineClient()
        return try await client.manualCommandPage(
            accountID: accountID,
            sourceID: sourceID,
            beforeCommandID: beforeCommandID,
            limit: limit
        )
    }

    public func control(line: String, context: AgentRequestContext) async throws -> String {
        let client = try await supervisor.engineClient()
        return try await client.control(line: line, context: context)
    }

    public func discardProposals() async throws -> Int {
        let client = try await supervisor.engineClient()
        return try await client.discardProposals()
    }

    public func agentProposals() async throws -> [AgentProposal] {
        let client = try await supervisor.engineClient()
        return try await client.agentProposals()
    }

    public func approveProposal(id: String, digest: String) async throws -> AgentProposal {
        let client = try await supervisor.engineClient()
        return try await client.approveProposal(id: id, digest: digest)
    }

    public func rejectProposal(id: String) async throws -> AgentProposal {
        let client = try await supervisor.engineClient()
        return try await client.rejectProposal(id: id)
    }

    public func agentAudit(limit: Int = 50) async throws -> [AgentAuditEntry] {
        let client = try await supervisor.engineClient()
        return try await client.agentAudit(limit: limit)
    }

    public func assistantAsk(
        conversationID: String, text: String, context: AssistantAskContext,
        provider: TradingProviderConfiguration, providerAPIKey: String
    ) async throws -> String {
        let client = try await supervisor.engineClient()
        return try await client.assistantAsk(
            conversationID: conversationID, text: text, context: context, provider: provider,
            providerAPIKey: providerAPIKey)
    }

    public func assistantTurn(turnID: String, after: Int) async throws -> AssistantTurnPage {
        let client = try await supervisor.engineClient()
        return try await client.assistantTurn(turnID: turnID, after: after)
    }

    public func assistantCancel(turnID: String) async throws -> Bool {
        let client = try await supervisor.engineClient()
        return try await client.assistantCancel(turnID: turnID)
    }

    public func assistantReset() async throws {
        let client = try await supervisor.engineClient()
        try await client.assistantReset()
    }

    public func submitSelfTest(_ command: SelfTestCommand) async throws -> WorkflowView {
        let client = try await supervisor.engineClient()
        return try await client.submitSelfTest(command)
    }

    public func workflow(id commandID: String) async throws -> WorkflowView {
        let client = try await supervisor.engineClient()
        return try await client.workflow(id: commandID)
    }
}
