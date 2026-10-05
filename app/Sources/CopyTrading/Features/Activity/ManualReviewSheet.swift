import DesktopCore
import SwiftUI

struct ManualReviewSheet: View {
    let source: SourceActivity
    let accounts: [AccountOverview]
    let operations: (any ManualReviewOperations)?
    let feature: ManualReviewFeatureModel

    @Environment(\.dismiss) private var dismiss
    @State private var correctionID = UUID().uuidString.lowercased()
    @State private var selectedAccountIDs: Set<String>
    @State private var actor = NSUserName()
    @State private var reason = ""
    @State private var instructions = [ManualInstructionDraft()]
    @State private var correctionRequest: ManualCorrectionRequest?
    @State private var previewRequests: [String: ManualPreviewRequest] = [:]
    @State private var confirmationRequests: [String: ManualConfirmationRequest] = [:]
    @State private var confirmationToSubmit: [ManualConfirmationRequest] = []
    @State private var showsConfirmation = false

    init(
        source: SourceActivity,
        copying: WaitingCall? = nil,
        accounts: [AccountOverview],
        operations: (any ManualReviewOperations)?,
        feature: ManualReviewFeatureModel
    ) {
        self.source = source
        self.accounts = accounts
        self.operations = operations
        self.feature = feature
        let available = Set(accounts.map(\.accountID))
        let needsReview = Set(source.destinations.filter { $0.status == "review_required" }.map(\.accountID))
        _selectedAccountIDs = State(initialValue: available.intersection(copying.map { Set($0.accountIDs) } ?? needsReview))
        // Copying fills in the calls the post waits on, for the owner to check before previewing.
        if let copying {
            if !copying.calls.isEmpty {
                _instructions = State(initialValue: copying.calls.map(ManualInstructionDraft.init(call:)))
            }
            _reason = State(initialValue: L10n.string("Copied a call that was waiting for me"))
        }
    }

    private var savedCorrection: ManualCorrectionRecord? {
        guard let correctionRequest else { return nil }
        return feature.corrections[correctionRequest.correctionID]?.correction
    }

    private var canSave: Bool {
        !selectedAccountIDs.isEmpty && !actor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.isEmpty
            && instructions.allSatisfy { $0.isValid }
    }

    private var readyConfirmationRequests: [ManualConfirmationRequest] {
        previewRequests.values.compactMap { previewRequest in
            guard let confirmation = confirmationRequests[previewRequest.previewID],
                let preview = feature.previews[previewRequest.previewID],
                preview.plan != nil, preview.reasons.isEmpty,
                feature.commandResults[confirmation.commandID] == nil
            else {
                return nil
            }
            return confirmation
        }.sorted { $0.accountID == $1.accountID ? $0.previewID < $1.previewID : $0.accountID < $1.accountID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(source.text)
                        .font(.title3)
                        .textSelection(.enabled)
                    LabeledContent(L10n.string("Received"), value: Humanize.timestamp(source.sourceAt))
                    LabeledContent(
                        L10n.string("Why it needs review"),
                        value: Reason.parserMessage(source.parserReason, needsReview: true)
                            ?? Reason.text("review_required")
                    )
                } header: {
                    Text(L10n.string("Message"))
                } footer: {
                    Text(L10n.string("The original message is never changed. Your correction is recorded separately."))
                }

                Section(L10n.string("Earlier outcomes")) {
                    if source.destinations.isEmpty {
                        Text(L10n.string("No prior account delivery details are recorded."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(source.destinations) { destination in
                        DestinationResultView(destination: destination)
                    }
                }

                Section {
                    if accounts.isEmpty {
                        ContentUnavailableView(
                            L10n.string("No account status is loaded"), systemImage: "person.crop.circle.badge.questionmark")
                    }
                    ForEach(accounts) { account in
                        Toggle(isOn: accountSelection(account.accountID)) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(account.accountID)
                                    EnvironmentBadge(environment: account.environment)
                                }
                                Text(
                                    L10n.string(
                                        "%@ · entries %@", L10n.string(Humanize.code(account.readiness)),
                                        L10n.string(Humanize.code(account.entryPermission)))
                                )
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .compactSwitch()
                        .disabled(correctionRequest != nil)
                    }
                } header: {
                    Text(L10n.string("Apply to accounts"))
                } footer: {
                    Text(
                        L10n.string(
                            "Each selected account is checked independently for permission, recovery, risk, activity, and ownership."))
                }

                Section(L10n.string("Correction")) {
                    TextField(L10n.string("Reviewed by"), text: $actor)
                        .disabled(correctionRequest != nil)
                    TextField(
                        L10n.string("Reason"), text: $reason, prompt: Text(L10n.string("Why the interpretation is being corrected")),
                        axis: .vertical
                    )
                    .accessibilityLabel(L10n.string("Reason"))
                    .lineLimit(2...4)
                    .disabled(correctionRequest != nil)
                }

                ForEach($instructions) { $instruction in
                    ManualInstructionSection(
                        instruction: $instruction,
                        index: instructions.firstIndex { $0.id == instruction.id } ?? 0,
                        canRemove: instructions.count > 1,
                        remove: { removeInstruction(instruction.id) }
                    )
                    .disabled(correctionRequest != nil)
                }

                Section {
                    Button(L10n.string("Add Instruction"), systemImage: "plus") { instructions.append(ManualInstructionDraft()) }
                        .buttonStyle(.borderless)
                        .disabled(correctionRequest != nil || instructions.count >= 20)
                    if correctionRequest == nil {
                        Button(L10n.string("Save Correction")) {
                            guard canSave else { return }
                            let request = ManualCorrectionRequest(
                                correctionID: correctionID,
                                sourceID: source.sourceID,
                                selectedAccountIDs: Array(selectedAccountIDs),
                                actor: actor.trimmingCharacters(in: .whitespacesAndNewlines),
                                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                                instructions: instructions.map(\.value)
                            )
                            correctionRequest = request
                            Task { await feature.saveCorrection(source: source, request: request, using: operations) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave || operations == nil)
                    } else if feature.canRetryCorrection(correctionID) {
                        Button(L10n.string("Retry Saving Correction")) {
                            Task {
                                await feature.retryCorrection(
                                    source: source, correctionID: correctionID, using: operations
                                )
                            }
                        }
                        .disabled(operations == nil || feature.pendingCorrections.contains(correctionID))
                    }
                    if let savedRequest = correctionRequest,
                        let savedOutcome = feature.corrections[savedRequest.correctionID]
                    {
                        LabeledContent(L10n.string("Correction revision"), value: savedOutcome.correction.revision.formatted())
                        ForEach(savedOutcome.accounts) { result in
                            StatusRow(
                                result.accountID, value: Humanize.code(result.reason ?? result.status),
                                tone: StatusTone(code: result.reason ?? result.status), localizesTitle: false)
                        }
                        Button(L10n.string("Start New Revision")) {
                            correctionID = UUID().uuidString.lowercased()
                            correctionRequest = nil
                            previewRequests = [:]
                            confirmationRequests = [:]
                        }
                        .accessibilityHint(L10n.string("Creates a new immutable correction identity for the same source."))
                    }
                    if let correctionRequest, let error = feature.errors[correctionRequest.correctionID] {
                        Callout(error, tone: .critical).accessibilityLabel(L10n.string("Correction error: %@", error))
                    }
                    if feature.pendingCorrections.contains(correctionID) {
                        ProgressView(L10n.string("Saving correction"))
                    }
                }

                if let savedCorrection {
                    Section {
                        Button(L10n.string(previewRequests.isEmpty ? "Preview Orders" : "Refresh Previews")) {
                            Task { await makePreviews(for: savedCorrection) }
                        }
                        .disabled(operations == nil || selectedAccountIDs.isEmpty || !feature.pendingPreviews.isEmpty)
                        ForEach(sortedPreviewRequests, id: \.previewID) { request in
                            previewRow(request)
                        }
                        if !readyConfirmationRequests.isEmpty {
                            Button(L10n.string("Review %@…", Humanize.count(readyConfirmationRequests.count, "Ready Order"))) {
                                confirmationToSubmit = readyConfirmationRequests
                                showsConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operations == nil || !feature.pendingCommands.isEmpty)
                        }
                        if !feature.pendingPreviews.isEmpty {
                            ProgressView(L10n.string("Checking current account and market state…"))
                                .controlSize(.small)
                        }
                    } header: {
                        Text(L10n.string("Order previews"))
                    } footer: {
                        Text(L10n.string("Previews read fresh market and account state. They never place or cancel an order."))
                    }
                }

                Section(L10n.string("Previous commands")) {
                    if feature.commandResults.values.filter({ $0.command.sourceID == source.sourceID }).isEmpty {
                        Text(L10n.string("No saved manual command results for this source."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(
                        feature.commandResults.values
                            .filter { $0.command.sourceID == source.sourceID }
                            .sorted { $0.command.confirmedAt > $1.command.confirmedAt }, id: \.command.request.commandID
                    ) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            StatusRow(
                                L10n.string(
                                    "%@ · instruction %lld", result.command.request.accountID, Int64(result.command.instructionIndex + 1)),
                                value: Humanize.code(result.status),
                                tone: StatusTone(code: result.status), localizesTitle: false
                            )
                            if let reason = result.reason {
                                Text(Humanize.code(reason)).font(.callout).foregroundStyle(.secondary)
                            }
                            if let orderStatus = result.orderStatus {
                                Text(
                                    L10n.string(
                                        "Order %@ · filled %@", L10n.string(Humanize.code(orderStatus).lowercased()), result.filledQuantity)
                                )
                                .font(.callout)
                            }
                            Button(L10n.string("Refresh Status")) {
                                Task {
                                    await feature.commandResult(
                                        accountID: result.command.request.accountID,
                                        commandID: result.command.request.commandID,
                                        using: operations
                                    )
                                }
                            }
                            .buttonStyle(.link)
                            .disabled(operations == nil || feature.pendingCommands.contains(result.command.request.commandID))
                        }
                        .help(L10n.string("Command %@", result.command.request.commandID))
                    }
                    ForEach(feature.commandPages.keys.sorted(), id: \.self) { accountID in
                        if feature.commandPages[accountID]?.nextBeforeCommandID != nil {
                            Button(L10n.string("Load earlier commands for %@", accountID)) {
                                Task {
                                    await feature.loadEarlierCommands(
                                        accountID: accountID, sourceID: source.sourceID, using: operations
                                    )
                                }
                            }
                            .disabled(feature.pendingCommandPages.contains(accountID))
                        }
                        if feature.pendingCommandPages.contains(accountID) {
                            ProgressView(L10n.string("Loading %@ command history", accountID))
                        }
                        if let error = feature.errors["history:\(accountID)"] {
                            Callout(error, tone: .critical)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.string("Review and Correct"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Close")) { dismiss() }
                }
            }
            .confirmationDialog(
                L10n.string("Confirm manual orders?"),
                isPresented: $showsConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.string("Confirm %lld order(s)", Int64(confirmationToSubmit.count)), role: .destructive) {
                    Task { await feature.confirm(confirmationToSubmit, using: operations) }
                }
                Button(L10n.string("Cancel"), role: .cancel) { confirmationToSubmit = [] }
            } message: {
                Text(confirmationSummary)
            }
            .task {
                feature.authorizePrivateEvidence()
                let accountIDs = Set(accounts.map(\.accountID) + source.destinations.map(\.accountID))
                await feature.recoverCommands(
                    sourceID: source.sourceID, accountIDs: accountIDs, using: operations
                )
            }
            .onDisappear { feature.clearPrivateEvidence() }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 640, idealHeight: 780)
    }

    private var sortedPreviewRequests: [ManualPreviewRequest] {
        previewRequests.values.sorted {
            $0.accountID == $1.accountID
                ? $0.instructionIndex < $1.instructionIndex
                : $0.accountID < $1.accountID
        }
    }

    @MainActor private var confirmationSummary: String {
        confirmationToSubmit.map { request in
            let preview = feature.previews[request.previewID]
            return
                L10n.string(
                    "%@: %@ %@ %@ at %@", request.accountID, preview?.plan?.side ?? "order",
                    preview?.plan?.quantity ?? "", preview?.plan?.symbol ?? "", preview?.plan?.limitPrice ?? "market"
                )
        }.joined(separator: "\n")
    }

    private func accountSelection(_ accountID: String) -> Binding<Bool> {
        Binding(
            get: { selectedAccountIDs.contains(accountID) },
            set: { selected in
                if selected { selectedAccountIDs.insert(accountID) } else { selectedAccountIDs.remove(accountID) }
            }
        )
    }

    private func removeInstruction(_ id: UUID) {
        instructions.removeAll { $0.id == id }
    }

    private func makePreviews(for correction: ManualCorrectionRecord) async {
        let recordedAccountIDs = Set(
            feature.corrections[correction.correctionID]?.accounts
                .filter { $0.status == "recorded" }
                .map(\.accountID) ?? []
        )
        for accountID in correction.selectedAccountIDs where recordedAccountIDs.contains(accountID) {
            for index in correction.instructions.indices {
                let key = "\(accountID):\(index)"
                if let action = await feature.refreshPreview(
                    accountID: accountID,
                    correctionID: correction.correctionID,
                    instructionIndex: index,
                    actor: actor.trimmingCharacters(in: .whitespacesAndNewlines),
                    using: operations
                ) {
                    previewRequests[key] = action.preview
                    confirmationRequests[action.preview.previewID] = action.confirmation
                }
            }
        }
    }

    @ViewBuilder
    private func previewRow(_ request: ManualPreviewRequest) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.string("%@ · instruction %lld", request.accountID, Int64(request.instructionIndex + 1)))
                .bold()
            if let preview = feature.previews[request.previewID] {
                if let plan = preview.plan {
                    Text(L10n.string("%@ %@ %@ · limit %@", plan.side.capitalized, plan.quantity, plan.symbol, plan.limitPrice ?? "market"))
                    if let lotID = plan.lotID {
                        Text(L10n.string("Owned lot: %@", lotID))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        L10n.string(
                            "Permitted quantity: %@ · original source age: %@ seconds", plan.quantity, String(preview.sourceAgeSeconds)))
                    Text(
                        L10n.string(
                            "Fresh quote %@ at %@ · preview expires %@", preview.freshPrice ?? "unavailable",
                            preview.quote?.timestamp ?? "unavailable", preview.expiresAt
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(L10n.string("Original source age at review: %@ seconds · %@", String(preview.sourceAgeSeconds), preview.sourceAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(preview.checks) { check in
                    StatusRow(
                        Humanize.code(check.name),
                        value: Humanize.code(check.reason ?? check.status),
                        tone: check.status == "blocked" ? .critical : StatusTone(code: check.status)
                    )
                    .font(.callout)
                }
                ForEach(preview.reasons, id: \.self) { reason in
                    Callout(L10n.string(Humanize.code(reason)), tone: .critical)
                }
                if let confirmation = confirmationRequests[request.previewID],
                    let outcome = feature.commandOutcomes[confirmation.commandID]
                {
                    Text(L10n.string("Command: %@", outcome.result?.status ?? outcome.error ?? "pending"))
                    if outcome.result != nil {
                        Button(L10n.string("Refresh command status")) {
                            Task {
                                await feature.commandResult(
                                    accountID: confirmation.accountID,
                                    commandID: confirmation.commandID,
                                    using: operations
                                )
                            }
                        }
                    }
                } else if let confirmation = confirmationRequests[request.previewID],
                    let error = feature.errors[confirmation.commandID]
                {
                    Text(error).foregroundStyle(.red)
                }
            } else if let error = feature.errors[request.previewID] {
                Text(error).foregroundStyle(.red)
            } else {
                Text(L10n.string("Preview is being checked or has not been requested."))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

}
