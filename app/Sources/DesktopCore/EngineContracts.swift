import Foundation

public enum EngineStage: String, Codable, Sendable {
    case captured
    case parsed
    case completed
    case failed
}

public enum SelfTestOutcome: String, Codable, Sendable {
    case simulated
}

public struct SelfTestCommand: Codable, Equatable, Identifiable, Sendable {
    public let commandID: String
    public let text: String
    public let destinationIDs: [String]

    public var id: String { commandID }

    public init(commandID: String, text: String, destinationIDs: [String]) {
        self.commandID = commandID
        self.text = text
        self.destinationIDs = destinationIDs
    }

    enum CodingKeys: String, CodingKey {
        case commandID = "command_id"
        case text
        case destinationIDs = "destination_ids"
    }
}

public struct DestinationOutcome: Codable, Equatable, Sendable {
    public let accountID: String
    public let result: SelfTestOutcome

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case result
    }
}

public struct WorkflowView: Codable, Equatable, Identifiable, Sendable {
    public let commandID: String
    public let stage: EngineStage
    public let outcomes: [DestinationOutcome]
    public let traceID: String

    public var id: String { commandID }

    enum CodingKeys: String, CodingKey {
        case commandID = "command_id"
        case stage
        case outcomes
        case traceID = "trace_id"
    }
}

public enum EngineState: String, Codable, Equatable, Sendable {
    case starting
    case running
    case stopping
    case failed
}

public enum TelemetryState: String, Codable, Equatable, Sendable {
    case healthy
    case degraded
}

public struct EngineDiagnosticCapture: Codable, Equatable, Sendable {
    public let sourceEvents: Int
    public let sourceEventGaps: Int
    public let modelRequests: Int
    public let modelRequestGaps: Int
    public let modelResponses: Int
    public let modelResponseGaps: Int

    enum CodingKeys: String, CodingKey {
        case sourceEvents = "source_events"
        case sourceEventGaps = "source_event_gaps"
        case modelRequests = "model_requests"
        case modelRequestGaps = "model_request_gaps"
        case modelResponses = "model_responses"
        case modelResponseGaps = "model_response_gaps"
    }
}

public struct EngineStatus: Codable, Equatable, Sendable {
    public let instanceID: String
    public let state: EngineState
    public let accepted: Int
    public let pending: Int
    public let completed: Int
    public let telemetryState: TelemetryState
    public let telemetryDropped: Int
    public let telemetryErrorCode: String?
    public let diagnosticCapture: EngineDiagnosticCapture

    enum CodingKeys: String, CodingKey {
        case instanceID = "instance_id"
        case state
        case accepted
        case pending
        case completed
        case telemetryState = "telemetry_state"
        case telemetryDropped = "telemetry_dropped"
        case telemetryErrorCode = "telemetry_error_code"
        case diagnosticCapture = "diagnostic_capture"
    }
}

public struct BackupMemberView: Codable, Equatable, Sendable {
    public let path: String
    public let size: Int
    public let sha256: String
    public let schemaVersion: String

    enum CodingKeys: String, CodingKey {
        case path
        case size
        case sha256
        case schemaVersion = "schema_version"
    }
}

public struct BackupManifestView: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let createdAt: String
    public let installationID: String
    public let environmentIDs: [String]
    public let members: [BackupMemberView]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case createdAt = "created_at"
        case installationID = "installation_id"
        case environmentIDs = "environment_ids"
        case members
    }
}

public struct RestorePreviewView: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let createdAt: String
    public let installationID: String
    public let matchesInstallation: Bool
    public let environmentIDs: [String]
    public let accountIDs: [String]
    public let credentialReferences: [String]
    public let stagingID: String
    public let members: [BackupMemberView]

    public init(
        formatVersion: Int,
        createdAt: String,
        installationID: String,
        matchesInstallation: Bool,
        environmentIDs: [String],
        accountIDs: [String],
        credentialReferences: [String],
        stagingID: String,
        members: [BackupMemberView]
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.installationID = installationID
        self.matchesInstallation = matchesInstallation
        self.environmentIDs = environmentIDs
        self.accountIDs = accountIDs
        self.credentialReferences = credentialReferences
        self.stagingID = stagingID
        self.members = members
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case createdAt = "created_at"
        case installationID = "installation_id"
        case matchesInstallation = "matches_installation"
        case environmentIDs = "environment_ids"
        case accountIDs = "account_ids"
        case credentialReferences = "credential_references"
        case stagingID = "staging_id"
        case members
    }
}

public struct RestorePreflightAccount: Codable, Equatable, Sendable {
    public let accountID: String
    public let environment: TradingEnvironment
    public let key: String
    public let secret: String

    public init(accountID: String, environment: TradingEnvironment, key: String, secret: String) {
        self.accountID = accountID
        self.environment = environment
        self.key = key
        self.secret = secret
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case environment
        case key
        case secret
    }
}

public struct RestorePreflightView: Codable, Equatable, Sendable {
    public let candidateID: String
    public let eligible: Bool
    public let checkedAccountCount: Int
    public let blockers: [String]
    public let completionToken: String?

    public init(
        candidateID: String,
        eligible: Bool,
        checkedAccountCount: Int,
        blockers: [String],
        completionToken: String?
    ) {
        self.candidateID = candidateID
        self.eligible = eligible
        self.checkedAccountCount = checkedAccountCount
        self.blockers = blockers
        self.completionToken = completionToken
    }

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case eligible
        case checkedAccountCount = "checked_account_count"
        case blockers
        case completionToken = "completion_token"
    }
}

public struct PendingRestoreCandidateView: Codable, Equatable, Sendable {
    public let candidateID: String
    public let previousGeneration: String
    public let activeGeneration: String
    public let installationID: String
    public let environmentIDs: [String]
    public let accountIDs: [String]
    public let credentialReferences: [String]
    public let candidateValid: Bool

    public init(
        candidateID: String,
        previousGeneration: String,
        activeGeneration: String,
        installationID: String,
        environmentIDs: [String],
        accountIDs: [String],
        credentialReferences: [String],
        candidateValid: Bool
    ) {
        self.candidateID = candidateID
        self.previousGeneration = previousGeneration
        self.activeGeneration = activeGeneration
        self.installationID = installationID
        self.environmentIDs = environmentIDs
        self.accountIDs = accountIDs
        self.credentialReferences = credentialReferences
        self.candidateValid = candidateValid
    }

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case previousGeneration = "previous_generation"
        case activeGeneration = "active_generation"
        case installationID = "installation_id"
        case environmentIDs = "environment_ids"
        case accountIDs = "account_ids"
        case credentialReferences = "credential_references"
        case candidateValid = "candidate_valid"
    }
}

public enum EngineResult: Equatable, Sendable {
    case workflow(WorkflowView)
    case status(EngineStatus)
    case trading(TradingStatus)
    case tradingActivation(TradingActivationStatus)
    case tradingValidation(TradingValidation)
    case connectionCheck(TradingCapabilityCheck)
    case accountControl(AccountControlResult)
    case ownershipResolution(OwnershipResolution)
    case accounts(AccountOverviewPage)
    case sourceActivity(SourceActivityPage)
    case profileEvaluation(ProfileEvaluation)
    case profileExampleReview(ProfileExampleReview)
    case learnedPlaybook(LearnedGuruPlaybook)
    case guruReplay(GuruReplay)
    case accountEvents(AccountEventPage)
    case equityHistory(accountID: String, history: EquityHistory?)
    case manualCorrection(ManualCorrectionOutcome)
    case manualPreview(ManualOrderPreview)
    case lotSalePreview(LotSalePreview)
    case lotSale(LotSaleResult)
    case manualCommands(ManualCommandsOutcome)
    case manualCommand(ManualCommandResult)
    case manualCommandPage(ManualCommandPage)
    case backup(BackupManifestView)
    case restorePreview(RestorePreviewView)
    case restoreCandidate(String)
    case restoreCandidateStatus(PendingRestoreCandidateView?)
    case restoreAborted(String)
    case restorePreflight(RestorePreflightView)
    case restoreActivated(String)
    case control(line: String)
    case proposalsDiscarded(Int)
    case agentProposals([AgentProposal])
    case agentProposal(AgentProposal)
    case agentAudit([AgentAuditEntry])
    case assistantTurnStarted(String)
    case assistantTurn(AssistantTurnPage)
    case assistantCancelled(Bool)
    case assistantReset
    case stopping
}

public enum EngineErrorCode: String, Codable, Equatable, Sendable {
    case invalidRequest = "invalid_request"
    case identityConflict = "identity_conflict"
    case unavailable
    case notFound = "not_found"
}

public struct EngineRemoteError: Codable, Equatable, Sendable {
    public let code: EngineErrorCode
    public let message: String?
}

public enum EngineContractError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case missingResult
    case conflictingResults
    case remote(code: EngineErrorCode, message: String?)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "The engine protocol version \(version) is not supported."
        case .missingResult:
            "The engine returned no result."
        case .conflictingResults:
            "The engine returned both a success and an error."
        case .remote(_, let message):
            message ?? "The engine could not complete that request."
        }
    }
}

public struct EngineResponse: Decodable, Sendable {
    public let version: Int
    public let requestID: String
    public let success: EngineSuccess?
    public let error: EngineRemoteError?

    enum CodingKeys: String, CodingKey {
        case version
        case requestID = "request_id"
        case success = "ok"
        case error
    }

    public func successValue() throws -> EngineResult {
        guard version == 1 else {
            throw EngineContractError.unsupportedVersion(version)
        }
        if let error {
            guard success == nil else { throw EngineContractError.conflictingResults }
            throw EngineContractError.remote(code: error.code, message: error.message)
        }
        guard let success else { throw EngineContractError.missingResult }
        return success.result
    }
}

public struct EngineSuccess: Decodable, Equatable, Sendable {
    public let result: EngineResult

    enum CodingKeys: String, CodingKey {
        case type
        case workflow
        case status
        case trading
        case activation
        case report
        case activationToken = "activation_token"
        case check
        case control
        case resolution
        case accounts
        case activity
        case events
        case correction
        case preview
        case commands
        case sale
        case manifest
        case candidateID = "candidate_id"
        case checkedAccountCount = "checked_account_count"
        case eligible
        case blockers
        case completionToken = "completion_token"
        case candidate
        case manualCommand = "command"
        case evaluation
        case review
        case playbook
        case replay
        case line
        case count
        case proposals
        case proposal
        case entries
        case accountID = "account_id"
        case history
        case turnID = "turn_id"
        case cancelled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "workflow":
            result = .workflow(try container.decode(WorkflowView.self, forKey: .workflow))
        case "status":
            result = .status(try container.decode(EngineStatus.self, forKey: .status))
        case "trading_status":
            result = .trading(try container.decode(TradingStatus.self, forKey: .trading))
        case "trading_activation":
            result = .tradingActivation(
                try container.decode(TradingActivationStatus.self, forKey: .activation)
            )
        case "trading_validation":
            result = .tradingValidation(
                TradingValidation(
                    report: try container.decode(TradingCapabilityReport.self, forKey: .report),
                    activationToken: try container.decodeIfPresent(String.self, forKey: .activationToken)
                ))
        case "connection_check":
            result = .connectionCheck(try container.decode(TradingCapabilityCheck.self, forKey: .check))
        case "account_control":
            result = .accountControl(try container.decode(AccountControlResult.self, forKey: .control))
        case "ownership_resolution":
            result = .ownershipResolution(try container.decode(OwnershipResolution.self, forKey: .resolution))
        case "accounts":
            result = .accounts(try container.decode(AccountOverviewPage.self, forKey: .accounts))
        case "source_activity":
            result = .sourceActivity(try container.decode(SourceActivityPage.self, forKey: .activity))
        case "profile_evaluation":
            result = .profileEvaluation(try container.decode(ProfileEvaluation.self, forKey: .evaluation))
        case "profile_example_review":
            result = .profileExampleReview(
                try container.decode(ProfileExampleReview.self, forKey: .review)
            )
        case "learned_playbook":
            result = .learnedPlaybook(
                try container.decode(LearnedGuruPlaybook.self, forKey: .playbook)
            )
        case "guru_replay":
            result = .guruReplay(try container.decode(GuruReplay.self, forKey: .replay))
        case "account_events":
            result = .accountEvents(try container.decode(AccountEventPage.self, forKey: .events))
        case "equity_history":
            result = .equityHistory(
                accountID: try container.decode(String.self, forKey: .accountID),
                history: try container.decodeIfPresent(EquityHistory.self, forKey: .history)
            )
        case "manual_correction":
            result = .manualCorrection(
                try container.decode(ManualCorrectionOutcome.self, forKey: .correction)
            )
        case "manual_preview":
            result = .manualPreview(try container.decode(ManualOrderPreview.self, forKey: .preview))
        case "lot_sale_preview":
            result = .lotSalePreview(try container.decode(LotSalePreview.self, forKey: .preview))
        case "lot_sale":
            result = .lotSale(try container.decode(LotSaleResult.self, forKey: .sale))
        case "manual_commands":
            result = .manualCommands(
                try container.decode(ManualCommandsOutcome.self, forKey: .commands)
            )
        case "manual_command":
            result = .manualCommand(
                try container.decode(ManualCommandResult.self, forKey: .manualCommand)
            )
        case "manual_command_page":
            result = .manualCommandPage(
                try container.decode(ManualCommandPage.self, forKey: .commands)
            )
        case "backup":
            result = .backup(try container.decode(BackupManifestView.self, forKey: .manifest))
        case "restore_preview":
            result = .restorePreview(try container.decode(RestorePreviewView.self, forKey: .preview))
        case "restore_candidate":
            result = .restoreCandidate(try container.decode(String.self, forKey: .candidateID))
        case "restore_candidate_status":
            result = .restoreCandidateStatus(
                try container.decodeIfPresent(
                    PendingRestoreCandidateView.self,
                    forKey: .candidate
                ))
        case "restore_aborted":
            result = .restoreAborted(try container.decode(String.self, forKey: .candidateID))
        case "restore_preflight":
            result = .restorePreflight(
                RestorePreflightView(
                    candidateID: try container.decode(String.self, forKey: .candidateID),
                    eligible: try container.decode(Bool.self, forKey: .eligible),
                    checkedAccountCount: try container.decode(Int.self, forKey: .checkedAccountCount),
                    blockers: try container.decode([String].self, forKey: .blockers),
                    completionToken: try container.decodeIfPresent(String.self, forKey: .completionToken)
                ))
        case "restore_activated":
            result = .restoreActivated(try container.decode(String.self, forKey: .candidateID))
        case "control":
            result = .control(line: try container.decode(String.self, forKey: .line))
        case "proposals_discarded":
            result = .proposalsDiscarded(try container.decode(Int.self, forKey: .count))
        case "proposals":
            result = .agentProposals(try container.decode([AgentProposal].self, forKey: .proposals))
        case "proposal":
            result = .agentProposal(try container.decode(AgentProposal.self, forKey: .proposal))
        case "agent_audit":
            result = .agentAudit(try container.decode([AgentAuditEntry].self, forKey: .entries))
        case "assistant_turn_started":
            result = .assistantTurnStarted(try container.decode(String.self, forKey: .turnID))
        case "assistant_turn":
            result = .assistantTurn(try AssistantTurnPage(from: decoder))
        case "assistant_cancelled":
            result = .assistantCancelled(try container.decode(Bool.self, forKey: .cancelled))
        case "assistant_reset":
            result = .assistantReset
        case "stopping":
            result = .stopping
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown engine success result type."
            )
        }
    }
}

enum EngineOperation: Sendable {
    case submitSelfTest(SelfTestCommand)
    case workflow(String)
    case status
    case tradingStatus
    case tradingActivation(String)
    case validateTrading(TradingConfiguration, TradingSecrets)
    case checkConnection(TradingConnectionCheck)
    case startTrading(
        TradingConfiguration, TradingSecrets, validationToken: String, activationID: String
    )
    case pauseTrading
    case createBackup(String)
    case previewRestore(String)
    case prepareRestoreCandidate(String)
    case restoreCandidateStatus
    case abortRestoreCandidate(String)
    case restorePreflight(candidateID: String, accounts: [RestorePreflightAccount])
    case completeRestoreCandidate(candidateID: String, completionToken: String)
    case controlAccount(AccountControlCommand)
    case resolveOwnership(accountID: String, resolution: OwnershipResolutionRequest)
    case accounts(beforeAccountID: String?, limit: Int)
    case sourceActivity(beforeSeq: Int?, limit: Int)
    case evaluateHistoricalProfile(HistoricalProfileEvaluationRequest)
    case reviewProfileExamples(ProfileExampleReviewRequest)
    case learnGuruPlaybook(GuruPlaybookLearningRequest)
    case replayGuruPosts(GuruReplayRequest)
    case accountEvents(accountID: String, beforeSeq: Int?, limit: Int)
    case equityHistory(accountID: String, window: EquityHistoryWindow)
    case saveManualCorrection(ManualCorrectionRequest)
    case previewManualOrder(ManualPreviewRequest)
    case confirmManualOrders([ManualConfirmationRequest])
    case previewLotSale(LotSalePreviewRequest)
    case confirmLotSale(LotSaleConfirmation)
    case manualCommand(accountID: String, commandID: String)
    case manualCommandPage(
        accountID: String, sourceID: String, beforeCommandID: String?, limit: Int
    )
    case control(line: String, context: AgentRequestContext)
    case discardProposals
    case listProposals
    case approveProposal(id: String, digest: String)
    case rejectProposal(id: String)
    case agentAudit(limit: Int)
    case assistantAsk(
        conversationID: String, text: String, context: AssistantAskContext,
        provider: TradingProviderConfiguration, providerAPIKey: String
    )
    case assistantTurn(turnID: String, after: Int)
    case assistantCancel(turnID: String)
    case assistantReset
    case stop
}

struct EngineRequest: Encodable, Sendable {
    let requestID: String
    let operation: EngineOperation

    enum CodingKeys: String, CodingKey {
        case version
        case requestID = "request_id"
        case operation
        case command
        case resolution
        case commandID = "command_id"
        case configuration
        case secrets
        case connection
        case validationToken = "validation_token"
        case activationID = "activation_id"
        case beforeSeq = "before_seq"
        case beforeAccountID = "before_account_id"
        case limit
        case accountID = "account_id"
        case sourceID = "source_id"
        case beforeCommandID = "before_command_id"
        case profile
        case review
        case provider
        case providerAPIKey = "provider_api_key"
        case destinations
        case channelID = "channel_id"
        case authorID = "author_id"
        case discordToken = "discord_token"
        case correction
        case preview
        case commands
        case sale
        case destination
        case archivePath = "archive_path"
        case stagingID = "staging_id"
        case candidateID = "candidate_id"
        case accounts
        case completionToken = "completion_token"
        case candidate
        case line
        case context
        case proposalID = "proposal_id"
        case digest
        case window
        case conversationID = "conversation_id"
        case text
        case turnID = "turn_id"
        case after
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(requestID, forKey: .requestID)
        switch operation {
        case .submitSelfTest(let command):
            try container.encode("submit_self_test", forKey: .operation)
            try container.encode(command, forKey: .command)
        case .workflow(let commandID):
            try container.encode("get_workflow", forKey: .operation)
            try container.encode(commandID, forKey: .commandID)
        case .status:
            try container.encode("get_status", forKey: .operation)
        case .tradingStatus:
            try container.encode("get_trading_status", forKey: .operation)
        case .tradingActivation(let activationID):
            try container.encode("get_trading_activation", forKey: .operation)
            try container.encode(activationID, forKey: .activationID)
        case .validateTrading(let configuration, let secrets):
            try container.encode("validate_trading", forKey: .operation)
            try container.encode(configuration, forKey: .configuration)
            try container.encode(secrets, forKey: .secrets)
        case .checkConnection(let connection):
            try container.encode("check_connection", forKey: .operation)
            try container.encode(connection, forKey: .connection)
        case .startTrading(let configuration, let secrets, let validationToken, let activationID):
            try container.encode("start_trading", forKey: .operation)
            try container.encode(configuration, forKey: .configuration)
            try container.encode(secrets, forKey: .secrets)
            try container.encode(validationToken, forKey: .validationToken)
            try container.encode(activationID, forKey: .activationID)
        case .pauseTrading:
            try container.encode("pause_trading", forKey: .operation)
        case .createBackup(let destination):
            try container.encode("create_backup", forKey: .operation)
            try container.encode(destination, forKey: .destination)
        case .previewRestore(let archivePath):
            try container.encode("preview_restore", forKey: .operation)
            try container.encode(archivePath, forKey: .archivePath)
        case .prepareRestoreCandidate(let stagingID):
            try container.encode("prepare_restore_candidate", forKey: .operation)
            try container.encode(stagingID, forKey: .stagingID)
        case .restoreCandidateStatus:
            try container.encode("restore_candidate_status", forKey: .operation)
        case .abortRestoreCandidate(let candidateID):
            try container.encode("abort_restore_candidate", forKey: .operation)
            try container.encode(candidateID, forKey: .candidateID)
        case .restorePreflight(let candidateID, let accounts):
            try container.encode("restore_preflight", forKey: .operation)
            try container.encode(candidateID, forKey: .candidateID)
            try container.encode(accounts, forKey: .accounts)
        case .completeRestoreCandidate(let candidateID, let completionToken):
            try container.encode("complete_restore_candidate", forKey: .operation)
            try container.encode(candidateID, forKey: .candidateID)
            try container.encode(completionToken, forKey: .completionToken)
        case .controlAccount(let command):
            try container.encode("control_account", forKey: .operation)
            try container.encode(command, forKey: .command)
        case .resolveOwnership(let accountID, let resolution):
            try container.encode("resolve_ownership", forKey: .operation)
            try container.encode(accountID, forKey: .accountID)
            try container.encode(resolution, forKey: .resolution)
        case .accounts(let beforeAccountID, let limit):
            try container.encode("get_accounts", forKey: .operation)
            try container.encodeIfPresent(beforeAccountID, forKey: .beforeAccountID)
            try container.encode(limit, forKey: .limit)
        case .sourceActivity(let beforeSeq, let limit):
            try container.encode("get_source_activity", forKey: .operation)
            try container.encodeIfPresent(beforeSeq, forKey: .beforeSeq)
            try container.encode(limit, forKey: .limit)
        case .evaluateHistoricalProfile(let evaluation):
            try container.encode("evaluate_historical_profile", forKey: .operation)
            try container.encode(evaluation.sourceID, forKey: .sourceID)
            try container.encode(evaluation.profile, forKey: .profile)
            try container.encode(evaluation.provider, forKey: .provider)
            try container.encode(evaluation.providerAPIKey, forKey: .providerAPIKey)
            try container.encode(evaluation.destinations, forKey: .destinations)
        case .reviewProfileExamples(let reviewRequest):
            try container.encode("review_profile_examples", forKey: .operation)
            try container.encode(reviewRequest.profile, forKey: .profile)
            try container.encode(reviewRequest.provider, forKey: .provider)
            try container.encode(reviewRequest.providerAPIKey, forKey: .providerAPIKey)
            try container.encode(reviewRequest.destinations, forKey: .destinations)
        case .learnGuruPlaybook(let learning):
            try container.encode("learn_guru_playbook", forKey: .operation)
            try container.encode(learning.channelID, forKey: .channelID)
            try container.encodeIfPresent(learning.authorID, forKey: .authorID)
            try container.encode(learning.discordToken, forKey: .discordToken)
            try container.encode(learning.provider, forKey: .provider)
            try container.encode(learning.providerAPIKey, forKey: .providerAPIKey)
        case .replayGuruPosts(let replay):
            try container.encode("replay_guru_posts", forKey: .operation)
            try container.encode(replay.channelID, forKey: .channelID)
            try container.encodeIfPresent(replay.authorID, forKey: .authorID)
            try container.encode(replay.discordToken, forKey: .discordToken)
            try container.encode(replay.provider, forKey: .provider)
            try container.encode(replay.providerAPIKey, forKey: .providerAPIKey)
            try container.encode(replay.profile, forKey: .profile)
            try container.encode(replay.destinations, forKey: .destinations)
        case .accountEvents(let accountID, let beforeSeq, let limit):
            try container.encode("get_account_events", forKey: .operation)
            try container.encode(accountID, forKey: .accountID)
            try container.encodeIfPresent(beforeSeq, forKey: .beforeSeq)
            try container.encode(limit, forKey: .limit)
        case .equityHistory(let accountID, let window):
            try container.encode("get_equity_history", forKey: .operation)
            try container.encode(accountID, forKey: .accountID)
            try container.encode(window, forKey: .window)
        case .saveManualCorrection(let correction):
            try container.encode("save_manual_correction", forKey: .operation)
            try container.encode(correction, forKey: .correction)
        case .previewManualOrder(let preview):
            try container.encode("preview_manual_order", forKey: .operation)
            try container.encode(preview, forKey: .preview)
        case .confirmManualOrders(let commands):
            try container.encode("confirm_manual_orders", forKey: .operation)
            try container.encode(commands, forKey: .commands)
        case .previewLotSale(let preview):
            try container.encode("preview_lot_sale", forKey: .operation)
            try container.encode(preview, forKey: .preview)
        case .confirmLotSale(let sale):
            try container.encode("confirm_lot_sale", forKey: .operation)
            try container.encode(sale, forKey: .sale)
        case .manualCommand(let accountID, let commandID):
            try container.encode("get_manual_command", forKey: .operation)
            try container.encode(accountID, forKey: .accountID)
            try container.encode(commandID, forKey: .commandID)
        case .manualCommandPage(let accountID, let sourceID, let beforeCommandID, let limit):
            try container.encode("list_manual_commands", forKey: .operation)
            try container.encode(accountID, forKey: .accountID)
            try container.encode(sourceID, forKey: .sourceID)
            try container.encodeIfPresent(beforeCommandID, forKey: .beforeCommandID)
            try container.encode(limit, forKey: .limit)
        case .control(let line, let context):
            try container.encode("control", forKey: .operation)
            try container.encode(line, forKey: .line)
            try container.encode(context, forKey: .context)
        case .discardProposals:
            try container.encode("discard_proposals", forKey: .operation)
        case .listProposals:
            try container.encode("list_proposals", forKey: .operation)
        case .approveProposal(let id, let digest):
            try container.encode("approve_proposal", forKey: .operation)
            try container.encode(id, forKey: .proposalID)
            try container.encode(digest, forKey: .digest)
        case .rejectProposal(let id):
            try container.encode("reject_proposal", forKey: .operation)
            try container.encode(id, forKey: .proposalID)
        case .agentAudit(let limit):
            try container.encode("agent_audit", forKey: .operation)
            try container.encode(limit, forKey: .limit)
        case .assistantAsk(let conversationID, let text, let context, let provider, let providerAPIKey):
            try container.encode("assistant_ask", forKey: .operation)
            try container.encode(conversationID, forKey: .conversationID)
            try container.encode(text, forKey: .text)
            try container.encode(context, forKey: .context)
            try container.encode(provider, forKey: .provider)
            try container.encode(providerAPIKey, forKey: .providerAPIKey)
        case .assistantTurn(let turnID, let after):
            try container.encode("assistant_turn", forKey: .operation)
            try container.encode(turnID, forKey: .turnID)
            try container.encode(after, forKey: .after)
        case .assistantCancel(let turnID):
            try container.encode("assistant_cancel", forKey: .operation)
            try container.encode(turnID, forKey: .turnID)
        case .assistantReset:
            try container.encode("assistant_reset", forKey: .operation)
        case .stop:
            try container.encode("stop", forKey: .operation)
        }
    }
}
