import Foundation
import Observation

/// The narrow private IPC surface used by the reviewed manual workflow.
public protocol ManualReviewOperations: Sendable {
    func saveManualCorrection(_ correction: ManualCorrectionRequest) async throws -> ManualCorrectionOutcome
    func previewManualOrder(_ preview: ManualPreviewRequest) async throws -> ManualOrderPreview
    func confirmManualOrders(_ commands: [ManualConfirmationRequest]) async throws -> ManualCommandsOutcome
    func manualCommandResult(accountID: String, commandID: String) async throws -> ManualCommandResult
    func manualCommandPage(
        accountID: String, sourceID: String, beforeCommandID: String?, limit: Int
    ) async throws -> ManualCommandPage
}

extension EngineClient: ManualReviewOperations {}
extension EngineActions: ManualReviewOperations {}

public struct ManualPreviewAction: Equatable, Sendable {
    public let preview: ManualPreviewRequest
    public let confirmation: ManualConfirmationRequest
}

/// Owns private correction, preview, and command evidence for one unlocked session.
@MainActor
@Observable
public final class ManualReviewFeatureModel {
    public private(set) var corrections: [String: ManualCorrectionOutcome] = [:]
    public private(set) var previews: [String: ManualOrderPreview] = [:]
    public private(set) var commandOutcomes: [String: ManualAccountCommandResult] = [:]
    public private(set) var commandResults: [String: ManualCommandResult] = [:]
    public private(set) var commandPages: [String: ManualCommandPage] = [:]
    public private(set) var errors: [String: String] = [:]
    public private(set) var pendingCorrections: Set<String> = []
    public private(set) var pendingPreviews: Set<String> = []
    public private(set) var pendingCommands: Set<String> = []
    public private(set) var pendingCommandPages: Set<String> = []

    private var privateAccessGeneration: UUID?
    private var correctionRequests: [String: ManualCorrectionRequest] = [:]
    private var previewRequests: [String: ManualPreviewRequest] = [:]
    private var confirmationRequests: [String: ManualConfirmationRequest] = [:]

    public init() {}

    public func authorizePrivateEvidence() {
        guard privateAccessGeneration == nil else { return }
        privateAccessGeneration = UUID()
    }

    public func saveCorrection(
        source: SourceActivity,
        request: ManualCorrectionRequest,
        using operations: (any ManualReviewOperations)?
    ) async {
        guard let operations, let generation = privateAccessGeneration else { return }
        // A post flagged for review, or a call held until the owner approves it (ADR-0008).
        guard source.decision == "review" || WaitingCall(source) != nil, source.sourceID == request.sourceID,
            source.captureStatus == "delivered"
        else {
            errors[request.correctionID] = "This source is not an available reviewed message."
            return
        }
        guard !request.selectedAccountIDs.isEmpty,
            request.selectedAccountIDs == Array(Set(request.selectedAccountIDs)).sorted(),
            !request.instructions.isEmpty
        else {
            errors[request.correctionID] = "Select accounts and provide at least one instruction."
            return
        }
        if let previous = correctionRequests[request.correctionID], previous != request {
            errors[request.correctionID] = "This correction ID is already tied to different content."
            return
        }
        correctionRequests[request.correctionID] = request
        pendingCorrections.insert(request.correctionID)
        defer {
            if isCurrent(generation) { pendingCorrections.remove(request.correctionID) }
        }

        do {
            let outcome = try await operations.saveManualCorrection(request)
            guard isCurrent(generation) else { return }
            let saved = outcome.correction
            let differences = [
                ("correction", saved.correctionID == request.correctionID),
                ("source", saved.sourceID == request.sourceID),
                ("accounts", saved.selectedAccountIDs == request.selectedAccountIDs),
                ("actor", saved.actor == request.actor),
                ("reason", saved.reason == request.reason),
                ("instructions", saved.instructions == request.instructions),
                ("source revision", saved.sourceRevision == source.sourceRevision),
                ("source time", saved.sourceAt == source.sourceAt),
                ("source text", saved.sourceText == source.text),
                ("decision", saved.acceptedInterpretation.decision == source.decision),
            ].filter { !$0.1 }.map(\.0)
            guard differences.isEmpty else {
                #if DEBUG
                    FileHandle.standardError.write(Data("saved correction differs in: \(differences)\n".utf8))
                #endif
                errors[request.correctionID] = "The engine returned a different correction."
                return
            }
            corrections[request.correctionID] = outcome
            errors.removeValue(forKey: request.correctionID)
        } catch {
            guard isCurrent(generation) else { return }
            errors[request.correctionID] = error.localizedDescription
        }
    }

    public func canRetryCorrection(_ correctionID: String) -> Bool {
        guard let request = correctionRequests[correctionID] else { return false }
        guard !pendingCorrections.contains(correctionID) else { return false }
        guard let outcome = corrections[correctionID] else { return true }
        let recorded = Set(outcome.accounts.filter { $0.status == "recorded" }.map(\.accountID))
        return request.selectedAccountIDs.contains { !recorded.contains($0) }
    }

    public func retryCorrection(
        source: SourceActivity,
        correctionID: String,
        using operations: (any ManualReviewOperations)?
    ) async {
        guard canRetryCorrection(correctionID),
            let request = correctionRequests[correctionID]
        else { return }
        await saveCorrection(source: source, request: request, using: operations)
    }

    public func preview(
        _ request: ManualPreviewRequest,
        using operations: (any ManualReviewOperations)?
    ) async {
        guard let operations, let generation = privateAccessGeneration else { return }
        guard let correctionOutcome = corrections[request.correctionID],
            correctionOutcome.accounts.contains(where: {
                $0.accountID == request.accountID && $0.status == "recorded"
            })
        else {
            errors[request.previewID] = "Save the reviewed correction for this account first."
            return
        }
        let correction = correctionOutcome.correction
        guard
            correction.selectedAccountIDs.contains(request.accountID),
            correction.instructions.indices.contains(request.instructionIndex)
        else {
            errors[request.previewID] = "Save the reviewed correction for this account first."
            return
        }
        if let previous = previewRequests[request.previewID], previous != request {
            errors[request.previewID] = "This preview ID is already tied to different content."
            return
        }
        previewRequests[request.previewID] = request
        pendingPreviews.insert(request.previewID)
        defer {
            if isCurrent(generation) { pendingPreviews.remove(request.previewID) }
        }

        do {
            let preview = try await operations.previewManualOrder(request)
            guard isCurrent(generation) else { return }
            guard preview.request == request,
                preview.correctionRevision == correction.revision
            else {
                errors[request.previewID] = "The engine returned a different preview."
                return
            }
            previews[request.previewID] = preview
            errors.removeValue(forKey: request.previewID)
        } catch {
            guard isCurrent(generation) else { return }
            errors[request.previewID] = error.localizedDescription
        }
    }

    public func refreshPreview(
        accountID: String,
        correctionID: String,
        instructionIndex: Int,
        actor: String,
        using operations: (any ManualReviewOperations)?
    ) async -> ManualPreviewAction? {
        guard let outcome = corrections[correctionID],
            outcome.correction.selectedAccountIDs.contains(accountID),
            outcome.correction.instructions.indices.contains(instructionIndex),
            outcome.accounts.contains(where: {
                $0.accountID == accountID && $0.status == "recorded"
            })
        else {
            errors[correctionID] = "Save the reviewed correction for this account first."
            return nil
        }
        let preview = ManualPreviewRequest(
            previewID: UUID().uuidString.lowercased(), accountID: accountID,
            correctionID: correctionID, instructionIndex: instructionIndex
        )
        let confirmation = ManualConfirmationRequest(
            commandID: UUID().uuidString.lowercased(), previewID: preview.previewID,
            accountID: accountID, actor: actor
        )
        await self.preview(preview, using: operations)
        return ManualPreviewAction(preview: preview, confirmation: confirmation)
    }

    public func confirm(
        _ requests: [ManualConfirmationRequest],
        using operations: (any ManualReviewOperations)?
    ) async {
        guard let operations, let generation = privateAccessGeneration, !requests.isEmpty else { return }
        var eligible: [ManualConfirmationRequest] = []
        var commandIDs = Set<String>()
        for request in requests {
            guard commandIDs.insert(request.commandID).inserted else {
                errors[request.commandID] = "A confirmation batch cannot repeat a command ID."
                continue
            }
            guard let preview = previews[request.previewID],
                preview.request.accountID == request.accountID,
                preview.plan != nil, preview.reasons.isEmpty
            else {
                errors[request.commandID] = "A ready preview is required before confirmation."
                continue
            }
            if let previous = confirmationRequests[request.commandID], previous != request {
                errors[request.commandID] = "This command ID is already tied to different content."
                continue
            }
            confirmationRequests[request.commandID] = request
            eligible.append(request)
        }
        guard !eligible.isEmpty else { return }
        let pendingIDs = Set(eligible.map(\.commandID))
        pendingCommands.formUnion(pendingIDs)
        defer {
            if isCurrent(generation) { pendingCommands.subtract(pendingIDs) }
        }

        let commandsByAccount = Dictionary(grouping: eligible, by: \.accountID)
        for accountID in commandsByAccount.keys.sorted() {
            guard let accountCommands = commandsByAccount[accountID] else { continue }
            do {
                let outcome = try await operations.confirmManualOrders(accountCommands)
                guard isCurrent(generation) else { return }
                let received = Set(outcome.outcomes.map(\.commandID))
                for item in outcome.outcomes {
                    guard let requested = accountCommands.first(where: { $0.commandID == item.commandID }),
                        requested.accountID == item.accountID
                    else {
                        errors[item.commandID] = "The engine returned a result for a different command."
                        continue
                    }
                    commandOutcomes[item.commandID] = item
                    if let result = item.result {
                        commandResults[item.commandID] = result
                        errors.removeValue(forKey: item.commandID)
                    } else if let error = item.error {
                        errors[item.commandID] = error
                    }
                }
                for request in accountCommands where !received.contains(request.commandID) {
                    errors[request.commandID] = "The engine returned no result for this account."
                }
            } catch {
                guard isCurrent(generation) else { return }
                for request in accountCommands { errors[request.commandID] = error.localizedDescription }
            }
        }
    }

    public func commandResult(
        accountID: String,
        commandID: String,
        using operations: (any ManualReviewOperations)?
    ) async {
        guard let operations, let generation = privateAccessGeneration,
            confirmationRequests[commandID]?.accountID == accountID
        else { return }
        pendingCommands.insert(commandID)
        defer {
            if isCurrent(generation) { pendingCommands.remove(commandID) }
        }
        do {
            let result = try await operations.manualCommandResult(
                accountID: accountID, commandID: commandID
            )
            guard isCurrent(generation) else { return }
            guard result.command.request.commandID == commandID,
                result.command.request.accountID == accountID
            else {
                errors[commandID] = "The engine returned a different command result."
                return
            }
            commandResults[commandID] = result
            errors.removeValue(forKey: commandID)
        } catch {
            guard isCurrent(generation) else { return }
            errors[commandID] = error.localizedDescription
        }
    }

    public func recoverCommands(
        sourceID: String,
        accountIDs: some Sequence<String>,
        using operations: (any ManualReviewOperations)?
    ) async {
        guard let operations, let generation = privateAccessGeneration else { return }
        for accountID in Set(accountIDs).sorted() {
            guard isCurrent(generation) else { return }
            pendingCommandPages.insert(accountID)
            defer { if isCurrent(generation) { pendingCommandPages.remove(accountID) } }
            do {
                let page = try await operations.manualCommandPage(
                    accountID: accountID, sourceID: sourceID, beforeCommandID: nil, limit: 50
                )
                guard isCurrent(generation) else { return }
                guard page.accountID == accountID, page.sourceID == sourceID,
                    page.items.allSatisfy({
                        $0.command.request.accountID == accountID
                            && $0.command.sourceID == sourceID
                    })
                else {
                    errors["history:\(accountID)"] = "The engine returned command history for a different account or source."
                    continue
                }
                commandPages[accountID] = page
                absorb(page.items)
                errors.removeValue(forKey: "history:\(accountID)")
            } catch {
                guard isCurrent(generation) else { return }
                errors["history:\(accountID)"] = error.localizedDescription
            }
        }
    }

    public func loadEarlierCommands(
        accountID: String,
        sourceID: String,
        using operations: (any ManualReviewOperations)?
    ) async {
        guard let operations, let generation = privateAccessGeneration,
            let current = commandPages[accountID],
            let cursor = current.nextBeforeCommandID
        else { return }
        pendingCommandPages.insert(accountID)
        defer { if isCurrent(generation) { pendingCommandPages.remove(accountID) } }
        do {
            let page = try await operations.manualCommandPage(
                accountID: accountID, sourceID: sourceID,
                beforeCommandID: cursor, limit: 50
            )
            guard isCurrent(generation) else { return }
            guard page.accountID == accountID, page.sourceID == sourceID,
                page.items.allSatisfy({
                    $0.command.request.accountID == accountID
                        && $0.command.sourceID == sourceID
                })
            else {
                errors["history:\(accountID)"] = "The engine returned command history for a different account or source."
                return
            }
            let combined = current.items + page.items
            commandPages[accountID] = ManualCommandPage(
                accountID: accountID, sourceID: sourceID, items: combined,
                nextBeforeCommandID: page.nextBeforeCommandID
            )
            absorb(page.items)
            errors.removeValue(forKey: "history:\(accountID)")
        } catch {
            guard isCurrent(generation) else { return }
            errors["history:\(accountID)"] = error.localizedDescription
        }
    }

    private func absorb(_ results: [ManualCommandResult]) {
        for result in results {
            let request = result.command.request
            confirmationRequests[request.commandID] = request
            commandResults[request.commandID] = result
            commandOutcomes[request.commandID] = ManualAccountCommandResult(
                accountID: request.accountID,
                commandID: request.commandID,
                result: result,
                error: nil
            )
            errors.removeValue(forKey: request.commandID)
        }
    }

    public func clearPrivateEvidence() {
        privateAccessGeneration = nil
        corrections = [:]
        previews = [:]
        commandOutcomes = [:]
        commandResults = [:]
        commandPages = [:]
        errors = [:]
        pendingCorrections = []
        pendingPreviews = []
        pendingCommands = []
        pendingCommandPages = []
        correctionRequests = [:]
        previewRequests = [:]
        confirmationRequests = [:]
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        privateAccessGeneration == generation
    }
}
