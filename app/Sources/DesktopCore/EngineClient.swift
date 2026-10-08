import Foundation

public actor EngineClient {
    private let transport: any EngineTransport
    private let requestTimeout: Duration
    private var pending: [String: CheckedContinuation<EngineResult, any Error>] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private var writeQueue: [PendingWrite] = []
    private var writerRunning = false
    private var readerStarted = false

    public init(transport: any EngineTransport, requestTimeout: Duration = .seconds(10)) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    public func submitSelfTest(_ command: SelfTestCommand) async throws -> WorkflowView {
        let result = try await request(.submitSelfTest(command))
        guard case .workflow(let workflow) = result else {
            throw EngineContractError.missingResult
        }
        return workflow
    }

    public func workflow(id commandID: String) async throws -> WorkflowView {
        let result = try await request(.workflow(commandID))
        guard case .workflow(let workflow) = result else {
            throw EngineContractError.missingResult
        }
        return workflow
    }

    public func status() async throws -> EngineStatus {
        let result = try await request(.status)
        guard case .status(let status) = result else {
            throw EngineContractError.missingResult
        }
        return status
    }

    public func tradingStatus() async throws -> TradingStatus {
        let result = try await request(.tradingStatus)
        guard case .trading(let status) = result else { throw EngineContractError.missingResult }
        return status
    }

    public func tradingActivation(activationID: String) async throws -> TradingActivationStatus {
        let result = try await request(.tradingActivation(activationID))
        guard case .tradingActivation(let status) = result else {
            throw EngineContractError.missingResult
        }
        return status
    }

    public func validateTrading(
        configuration: TradingConfiguration, secrets: TradingSecrets
    ) async throws -> TradingValidation {
        let result = try await request(.validateTrading(configuration, secrets))
        guard case .tradingValidation(let validation) = result else {
            throw EngineContractError.missingResult
        }
        return validation
    }

    public func checkConnection(_ connection: TradingConnectionCheck) async throws -> TradingCapabilityCheck {
        let result = try await request(.checkConnection(connection))
        guard case .connectionCheck(let check) = result else {
            throw EngineContractError.missingResult
        }
        return check
    }

    public func startTrading(
        configuration: TradingConfiguration,
        secrets: TradingSecrets,
        validationToken: String,
        activationID: String
    ) async throws -> TradingStatus {
        let result = try await request(
            .startTrading(
                configuration, secrets, validationToken: validationToken, activationID: activationID
            ))
        guard case .trading(let status) = result else { throw EngineContractError.missingResult }
        return status
    }

    public func pauseTrading() async throws -> TradingStatus {
        let result = try await request(.pauseTrading)
        guard case .trading(let status) = result else { throw EngineContractError.missingResult }
        return status
    }

    /// Hands copying a setup that changes only account limits; returns the setup's revision.
    public func updateAccountLimits(configuration: TradingConfiguration) async throws -> String {
        let result = try await request(.updateAccountLimits(configuration))
        guard case .accountLimits(let revision) = result else { throw EngineContractError.missingResult }
        return revision
    }

    public func createBackup(destination: URL) async throws -> BackupManifestView {
        let result = try await request(.createBackup(destination.path))
        guard case .backup(let manifest) = result else { throw EngineContractError.missingResult }
        return manifest
    }

    public func previewRestore(archive: URL) async throws -> RestorePreviewView {
        let result = try await request(.previewRestore(archive.path))
        guard case .restorePreview(let preview) = result else {
            throw EngineContractError.missingResult
        }
        return preview
    }

    public func prepareRestoreCandidate(stagingID: String) async throws -> String {
        let result = try await request(.prepareRestoreCandidate(stagingID))
        guard case .restoreCandidate(let candidateID) = result else {
            throw EngineContractError.missingResult
        }
        return candidateID
    }

    public func restoreCandidateStatus() async throws -> PendingRestoreCandidateView? {
        let result = try await request(.restoreCandidateStatus)
        guard case .restoreCandidateStatus(let pending) = result else {
            throw EngineContractError.missingResult
        }
        return pending
    }

    public func abortRestoreCandidate(candidateID: String) async throws {
        let result = try await request(.abortRestoreCandidate(candidateID))
        guard case .restoreAborted(let abortedID) = result, abortedID == candidateID else {
            throw EngineContractError.missingResult
        }
    }

    public func restorePreflight(
        candidateID: String, accounts: [RestorePreflightAccount]
    ) async throws -> RestorePreflightView {
        let result = try await request(.restorePreflight(candidateID: candidateID, accounts: accounts))
        guard case .restorePreflight(let preflight) = result else {
            throw EngineContractError.missingResult
        }
        return preflight
    }

    public func completeRestoreCandidate(
        candidateID: String, completionToken: String
    ) async throws {
        let result = try await request(
            .completeRestoreCandidate(
                candidateID: candidateID,
                completionToken: completionToken
            ))
        guard case .restoreActivated(let activatedID) = result,
            activatedID == candidateID
        else {
            throw EngineContractError.missingResult
        }
    }

    public func controlAccount(_ command: AccountControlCommand) async throws -> AccountControlResult {
        let result = try await request(.controlAccount(command))
        guard case .accountControl(let control) = result else { throw EngineContractError.missingResult }
        return control
    }

    public func resolveOwnership(
        accountID: String, resolution: OwnershipResolutionRequest
    ) async throws -> OwnershipResolution {
        let result = try await request(.resolveOwnership(accountID: accountID, resolution: resolution))
        guard case .ownershipResolution(let value) = result else { throw EngineContractError.missingResult }
        return value
    }

    public func accounts(
        beforeAccountID: String? = nil, limit: Int = 50
    ) async throws -> AccountOverviewPage {
        let result = try await request(.accounts(beforeAccountID: beforeAccountID, limit: limit))
        guard case .accounts(let page) = result else { throw EngineContractError.missingResult }
        return page
    }

    public func sourceActivity(beforeSeq: Int? = nil, limit: Int = 50) async throws -> SourceActivityPage {
        let result = try await request(.sourceActivity(beforeSeq: beforeSeq, limit: limit))
        guard case .sourceActivity(let page) = result else { throw EngineContractError.missingResult }
        return page
    }

    public func evaluateHistoricalProfile(
        _ evaluation: HistoricalProfileEvaluationRequest
    ) async throws -> ProfileEvaluation {
        let result = try await request(.evaluateHistoricalProfile(evaluation))
        guard case .profileEvaluation(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func reviewProfileExamples(
        _ reviewRequest: ProfileExampleReviewRequest
    ) async throws -> ProfileExampleReview {
        let result = try await request(.reviewProfileExamples(reviewRequest))
        guard case .profileExampleReview(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func learnGuruPlaybook(
        _ learning: GuruPlaybookLearningRequest
    ) async throws -> LearnedGuruPlaybook {
        let result = try await request(.learnGuruPlaybook(learning))
        guard case .learnedPlaybook(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func replayGuruPosts(_ replay: GuruReplayRequest) async throws -> GuruReplay {
        let result = try await request(.replayGuruPosts(replay))
        guard case .guruReplay(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func accountEvents(
        accountID: String, beforeSeq: Int? = nil, limit: Int = 50
    ) async throws -> AccountEventPage {
        let result = try await request(.accountEvents(accountID: accountID, beforeSeq: beforeSeq, limit: limit))
        guard case .accountEvents(let page) = result else { throw EngineContractError.missingResult }
        return page
    }

    public func equityHistory(
        accountID: String, window: EquityHistoryWindow
    ) async throws -> EquityHistory? {
        let result = try await request(.equityHistory(accountID: accountID, window: window))
        guard case .equityHistory(let resultAccountID, let history) = result, resultAccountID == accountID else {
            throw EngineContractError.missingResult
        }
        return history
    }

    public func saveManualCorrection(
        _ correction: ManualCorrectionRequest
    ) async throws -> ManualCorrectionOutcome {
        let result = try await request(.saveManualCorrection(correction))
        guard case .manualCorrection(let outcome) = result else {
            throw EngineContractError.missingResult
        }
        return outcome
    }

    public func previewManualOrder(
        _ preview: ManualPreviewRequest
    ) async throws -> ManualOrderPreview {
        let result = try await request(.previewManualOrder(preview))
        guard case .manualPreview(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func previewLotSale(_ preview: LotSalePreviewRequest) async throws -> LotSalePreview {
        let result = try await request(.previewLotSale(preview))
        guard case .lotSalePreview(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func confirmLotSale(_ sale: LotSaleConfirmation) async throws -> LotSaleResult {
        let result = try await request(.confirmLotSale(sale))
        guard case .lotSale(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func confirmManualOrders(
        _ commands: [ManualConfirmationRequest]
    ) async throws -> ManualCommandsOutcome {
        let result = try await request(.confirmManualOrders(commands))
        guard case .manualCommands(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func manualCommandResult(
        accountID: String, commandID: String
    ) async throws -> ManualCommandResult {
        let result = try await request(.manualCommand(accountID: accountID, commandID: commandID))
        guard case .manualCommand(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    public func manualCommandPage(
        accountID: String, sourceID: String, beforeCommandID: String? = nil, limit: Int = 50
    ) async throws -> ManualCommandPage {
        let result = try await request(
            .manualCommandPage(
                accountID: accountID,
                sourceID: sourceID,
                beforeCommandID: beforeCommandID,
                limit: limit
            ))
        guard case .manualCommandPage(let value) = result else {
            throw EngineContractError.missingResult
        }
        return value
    }

    /// Relay one agent request line; the engine answers with one contract line.
    public func control(line: String, context: AgentRequestContext) async throws -> String {
        let result = try await request(.control(line: line, context: context))
        guard case .control(let answer) = result else { throw EngineContractError.missingResult }
        return answer
    }

    /// Close every proposal still waiting for the owner, as when the app locks.
    public func discardProposals() async throws -> Int {
        let result = try await request(.discardProposals)
        guard case .proposalsDiscarded(let count) = result else {
            throw EngineContractError.missingResult
        }
        return count
    }

    public func agentProposals() async throws -> [AgentProposal] {
        let result = try await request(.listProposals)
        guard case .agentProposals(let proposals) = result else { throw EngineContractError.missingResult }
        return proposals
    }

    /// Perform a proposal the owner approved; the digest must match what the owner saw.
    public func approveProposal(id: String, digest: String) async throws -> AgentProposal {
        let result = try await request(.approveProposal(id: id, digest: digest))
        guard case .agentProposal(let proposal) = result else { throw EngineContractError.missingResult }
        return proposal
    }

    public func rejectProposal(id: String) async throws -> AgentProposal {
        let result = try await request(.rejectProposal(id: id))
        guard case .agentProposal(let proposal) = result else { throw EngineContractError.missingResult }
        return proposal
    }

    public func agentAudit(limit: Int = 50) async throws -> [AgentAuditEntry] {
        let result = try await request(.agentAudit(limit: limit))
        guard case .agentAudit(let entries) = result else { throw EngineContractError.missingResult }
        return entries
    }

    public func assistantAsk(
        conversationID: String, text: String, context: AssistantAskContext,
        provider: TradingProviderConfiguration, providerAPIKey: String
    ) async throws -> String {
        let result = try await request(
            .assistantAsk(
                conversationID: conversationID, text: text, context: context, provider: provider,
                providerAPIKey: providerAPIKey))
        guard case .assistantTurnStarted(let turnID) = result else { throw EngineContractError.missingResult }
        return turnID
    }

    public func assistantTurn(turnID: String, after: Int) async throws -> AssistantTurnPage {
        let result = try await request(.assistantTurn(turnID: turnID, after: after))
        guard case .assistantTurn(let page) = result, page.turnID == turnID else {
            throw EngineContractError.missingResult
        }
        return page
    }

    public func assistantCancel(turnID: String) async throws -> Bool {
        let result = try await request(.assistantCancel(turnID: turnID))
        guard case .assistantCancelled(let cancelled) = result else { throw EngineContractError.missingResult }
        return cancelled
    }

    public func assistantReset() async throws {
        let result = try await request(.assistantReset)
        guard case .assistantReset = result else { throw EngineContractError.missingResult }
    }

    public func stop() async throws {
        let result = try await request(.stop)
        guard case .stopping = result else {
            throw EngineContractError.missingResult
        }
    }

    private func request(_ operation: EngineOperation) async throws -> EngineResult {
        let requestID = UUID().uuidString.lowercased()
        let request = EngineRequest(requestID: requestID, operation: operation)
        var encoded: Data
        do {
            encoded = try JSONEncoder().encode(request)
        } catch {
            throw EngineTransportError.malformedResponse
        }
        guard encoded.count <= 1_048_576 else { throw EngineTransportError.requestTooLarge }
        encoded.append(10)
        let line = encoded

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[requestID] = continuation
                let timeout = requestTimeout
                timeoutTasks[requestID] = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        await self?.timeout(requestID: requestID)
                    } catch {
                        return
                    }
                }
                writeQueue.append(PendingWrite(requestID: requestID, line: line))
                ensureReader()
                scheduleWriter()
            }
        } onCancel: {
            Task { [weak self] in await self?.cancel(requestID: requestID) }
        }
    }

    private func ensureReader() {
        guard !readerStarted else { return }
        readerStarted = true
        Task { [weak self] in await self?.readResponses() }
    }

    private func scheduleWriter() {
        guard !writerRunning else { return }
        writerRunning = true
        Task { [weak self] in await self?.drainWrites() }
    }

    private func drainWrites() async {
        while !writeQueue.isEmpty {
            let write = writeQueue.removeFirst()
            do {
                try await transport.send(write.line)
            } catch {
                fail(requestID: write.requestID, with: error)
                failAll(EngineTransportError.disconnected)
                writeQueue.removeAll()
                writerRunning = false
                return
            }
        }
        writerRunning = false
        if !writeQueue.isEmpty { scheduleWriter() }
    }

    private func readResponses() async {
        let lines = await transport.responseLines()
        do {
            for try await line in lines {
                let response: EngineResponse
                do {
                    response = try JSONDecoder().decode(EngineResponse.self, from: line)
                } catch {
                    failAll(EngineTransportError.malformedResponse)
                    return
                }
                guard let continuation = pending.removeValue(forKey: response.requestID) else {
                    continue
                }
                timeoutTasks.removeValue(forKey: response.requestID)?.cancel()
                do {
                    continuation.resume(returning: try response.successValue())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            failAll(EngineTransportError.disconnected)
        } catch {
            failAll(EngineTransportError.disconnected)
        }
    }

    private func fail(requestID: String, with error: any Error) {
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
        pending.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    private func cancel(requestID: String) {
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
        pending.removeValue(forKey: requestID)?.resume(throwing: CancellationError())
    }

    private func timeout(requestID: String) {
        timeoutTasks.removeValue(forKey: requestID)
        pending.removeValue(forKey: requestID)?.resume(throwing: EngineTransportError.requestTimedOut)
    }

    private func failAll(_ error: any Error) {
        let continuations = pending.values
        pending.removeAll()
        for task in timeoutTasks.values { task.cancel() }
        timeoutTasks.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
    }
}

private struct PendingWrite: Sendable {
    let requestID: String
    let line: Data
}
