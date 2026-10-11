import DesktopCore
import SwiftUI

/// The owner says what a post should do and sends it: the post in big type, then plain choices
/// (buy or sell, the stock, how much, the price, the accounts), a one-line preview of the order,
/// and one button. Underneath it is the engine's manual correction: saved, previewed fresh in
/// each account, then confirmed (ADR-0007).
struct ManualReviewSheet: View {
    let source: SourceActivity
    let accounts: [AccountOverview]
    let operations: (any ManualReviewOperations)?
    let feature: ManualReviewFeatureModel
    let guruName: String?
    /// This guru's full position in each account it copies to, by account.
    let connections: [String: TradingRouteConnection]
    /// Asks for Touch ID when an order goes to a live account or one that asks to approve orders.
    let confirmOrders: (Set<String>) async throws -> Void
    /// The engine isn't running, so nothing can be saved or placed until it starts.
    let engineStopped: Bool
    let startEngine: () -> Void

    private let mode: ManualReviewMode
    /// The choices were filled in from the post's words, not from the reader.
    private let guessed: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var correctionID = UUID().uuidString.lowercased()
    @State private var selectedAccountIDs: Set<String>
    @State private var instructions: [ManualInstructionDraft]
    @State private var correctionRequest: ManualCorrectionRequest?
    @State private var previewRequests: [String: ManualPreviewRequest] = [:]
    @State private var confirmationRequests: [String: ManualConfirmationRequest] = [:]
    @State private var confirmationToSubmit: [ManualConfirmationRequest] = []
    @State private var showsConfirmation = false
    /// Confirmed orders wait here a few seconds before they leave, so they can be undone.
    @State private var isHolding = false
    @State private var approvalProblem: String?

    init(
        source: SourceActivity,
        copying: WaitingCall? = nil,
        accounts: [AccountOverview],
        operations: (any ManualReviewOperations)?,
        feature: ManualReviewFeatureModel,
        guruName: String? = nil,
        connections: [TradingRouteConnection] = [],
        confirmOrders: @escaping (Set<String>) async throws -> Void,
        engineStopped: Bool = false,
        startEngine: @escaping () -> Void = {}
    ) {
        self.source = source
        self.accounts = accounts
        self.operations = operations
        self.feature = feature
        self.guruName = guruName
        self.connections = Dictionary(connections.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })
        self.confirmOrders = confirmOrders
        self.engineStopped = engineStopped
        self.startEngine = startEngine
        mode = ManualReviewMode(copying: copying)
        let available = Set(accounts.map(\.accountID))
        let needsReview = Set(source.destinations.filter { $0.status == "review_required" }.map(\.accountID))
        let selected = available.intersection(copying.map { Set($0.accountIDs) } ?? needsReview)
        _selectedAccountIDs = State(initialValue: selected)

        // Copying fills in the calls the post waits on; otherwise the reader's reading, and when
        // it had none, the likeliest trade in the post's words.
        let calls =
            copying.map(\.calls).flatMap { $0.isEmpty ? nil : $0 } ?? (source.suggested.isEmpty ? source.instructions : source.suggested)
        var drafts = calls.map(ManualInstructionDraft.init(call:))
        let holdings = ManualHolding.holdings(in: accounts, accountIDs: selected)
        if drafts.isEmpty, let guess = ManualInstructionGuess.draft(from: source.readableText(), held: holdings.map(\.symbol)) {
            drafts = [guess]
            guessed = true
        } else {
            guessed = false
        }
        if drafts.isEmpty { drafts = [ManualInstructionDraft()] }
        let prices = Self.marketPrices(in: accounts)
        // A buy needs a price: with none in the post it follows the last price. A sell without one
        // sells at the market.
        for index in drafts.indices where !drafts[index].isSell && drafts[index].price.trimmed.isEmpty {
            if let market = prices[drafts[index].symbol.trimmed.uppercased()] { drafts[index].price = "\(market)" }
        }
        _instructions = State(initialValue: drafts)
    }

    // MARK: State

    /// The last save failed because the engine was gone, not because of the correction.
    private var engineDisconnected: Bool {
        guard let correctionRequest, let error = feature.errors[correctionRequest.correctionID] else { return false }
        return [
            EngineTransportError.disconnected.errorDescription, ProcessSupervisorError.missingEngineClient.errorDescription,
        ]
        .contains(error)
    }

    private var canSave: Bool {
        !selectedAccountIDs.isEmpty && !instructions.isEmpty && instructions.allSatisfy(\.isValid)
    }

    private var chosenAccounts: [AccountOverview] { accounts.filter { selectedAccountIDs.contains($0.accountID) } }

    private var estimate: ManualOrderEstimate {
        ManualOrderEstimate(drafts: instructions, accounts: chosenAccounts, connections: connections, mode: mode)
    }

    private var isChecking: Bool {
        feature.pendingCorrections.contains(correctionID) || !feature.pendingPreviews.isEmpty
    }

    private var hasSent: Bool {
        confirmationRequests.values.contains { feature.commandOutcomes[$0.commandID] != nil }
    }

    private var readyConfirmationRequests: [ManualConfirmationRequest] {
        previewRequests.values.compactMap { previewRequest in
            guard let confirmation = confirmationRequests[previewRequest.previewID],
                let preview = feature.previews[previewRequest.previewID],
                preview.plan != nil, preview.reasons.isEmpty,
                feature.commandResults[confirmation.commandID] == nil,
                feature.commandOutcomes[confirmation.commandID] == nil
            else {
                return nil
            }
            return confirmation
        }.sorted { $0.accountID == $1.accountID ? $0.previewID < $1.previewID : $0.accountID < $1.accountID }
    }

    private var sortedPreviewRequests: [ManualPreviewRequest] {
        previewRequests.values.sorted {
            $0.accountID == $1.accountID ? $0.instructionIndex < $1.instructionIndex : $0.accountID < $1.accountID
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(L10n.string("What should happen"))
                        trades
                    }
                    accountChoices
                    if correctionRequest != nil { results }
                    ManualReviewHistory(source: source, feature: feature, operations: operations)
                }
                .padding(.horizontal, 40)
                .padding(.top, 38)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            footer
        }
        .background(Palette.page)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 600, idealHeight: 780)
        .confirmationDialog(
            L10n.string("Confirm manual orders?"),
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("Confirm %lld order(s)", Int64(confirmationToSubmit.count)), role: .destructive) {
                Task { await send() }
            }
            Button(L10n.string("Cancel"), role: .cancel) { confirmationToSubmit = [] }
        } message: {
            Text(confirmationSummary)
        }
        .task {
            feature.authorizePrivateEvidence()
            let accountIDs = Set(accounts.map(\.accountID) + source.destinations.map(\.accountID))
            await feature.recoverCommands(sourceID: source.sourceID, accountIDs: accountIDs, using: operations)
        }
        .onDisappear { feature.clearPrivateEvidence() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(L10n.string(mode.label))
            let text = source.readableText()
            Text(text.isEmpty ? L10n.string("A post with no words") : "“\(text)”")
                .font(DisplayFont.font(size: text.count > 90 ? 24 : 34, weight: .medium, relativeTo: .title))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("review.post")
            Text(lede)
                .font(DesignTokens.lede)
                .tracking(DesignTokens.ledeTracking)
                .foregroundStyle(Palette.tertiaryInk)
            if mode == .enter {
                Text(
                    L10n.string(
                        guessed
                            ? "Filled in from the post's words. Check it, then send."
                            : "Say what this post should do, then send it.")
                )
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.top, 2)
            }
        }
    }

    @MainActor private var lede: String {
        [guruName, Humanize.postTime(source.sourceAt)].compactMap { $0 }.joined(separator: " · ")
    }

    private var trades: some View {
        VStack(alignment: .leading, spacing: 30) {
            let holdings = ManualHolding.holdings(in: accounts, accountIDs: selectedAccountIDs)
            let prices = Self.marketPrices(in: accounts)
            let single = chosenAccounts.count == 1 ? chosenAccounts.first.flatMap { connections[$0.accountID] } : nil
            ForEach($instructions) { $instruction in
                let index = instructions.firstIndex { $0.id == instruction.id } ?? 0
                ManualInstructionEditor(
                    draft: $instruction,
                    holdings: holdings,
                    marketPrices: prices,
                    fullPosition: single,
                    position: instructions.count > 1 ? (index, instructions.count) : nil,
                    remove: { instructions.removeAll { $0.id == instruction.id } }
                )
            }
            if correctionRequest == nil, instructions.count < 20 {
                Button {
                    instructions.append(ManualInstructionDraft())
                } label: {
                    Label(L10n.string("Another trade"), systemImage: "plus")
                        .font(DesignTokens.caption.weight(.medium))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .buttonStyle(QuietPressButtonStyle())
                .accessibilityIdentifier("review.addTrade")
            }
        }
        .disabled(correctionRequest != nil)
    }

    @ViewBuilder private var accountChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(L10n.string("Accounts"))
            if accounts.isEmpty {
                Text(L10n.string("No account status is loaded"))
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            FlowRow(spacing: 26, lineSpacing: 14) {
                ForEach(accounts) { account in
                    ChoiceWord(
                        title: account.accountID,
                        detail: L10n.string(account.environment == .live ? "Live" : "Paper"),
                        detailTint: account.environment == .live ? .orange : nil,
                        isOn: selectedAccountIDs.contains(account.accountID)
                    ) {
                        if selectedAccountIDs.contains(account.accountID) {
                            selectedAccountIDs.remove(account.accountID)
                        } else {
                            selectedAccountIDs.insert(account.accountID)
                        }
                    }
                    .accessibilityLabel(Text(account.accountID))
                    .accessibilityIdentifier("review.account.\(account.accountID)")
                }
            }
            .disabled(correctionRequest != nil)
            Text(L10n.string("Before anything is placed, CopyTrading checks each account's limits and what it holds."))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
        }
    }

    // MARK: After saving

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(L10n.string("Checked just now"))
            if let correctionRequest, let error = feature.errors[correctionRequest.correctionID] {
                Callout(L10n.string(error), tone: .critical)
                    .accessibilityLabel(L10n.string("Correction error: %@", L10n.string(error)))
            }
            if let saved = correctionRequest.flatMap({ feature.corrections[$0.correctionID] }) {
                ForEach(saved.accounts.filter { $0.status != "recorded" }) { result in
                    StatusRow(
                        result.accountID, value: Humanize.code(result.reason ?? result.status),
                        tone: StatusTone(code: result.reason ?? result.status), localizesTitle: false)
                }
            }
            ForEach(sortedPreviewRequests, id: \.previewID) { request in
                ManualPreviewResult(request: request, confirmation: confirmationRequests[request.previewID], feature: feature)
            }
            if isChecking {
                ProgressView(L10n.string("Checking current account and market state…"))
                    .controlSize(.small)
            }
            if let approvalProblem {
                Callout(approvalProblem, tone: .critical)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if engineStopped || engineDisconnected {
                HStack {
                    Callout(L10n.string("CopyTrading's engine isn't running, so this can't be saved or placed yet."), tone: .caution)
                    Button(L10n.string("Start Engine"), action: startEngine)
                        .buttonStyle(InkActionButtonStyle(isProminent: false))
                }
            }
            if isHolding {
                OrderHold(
                    title: L10n.string("Placing %lld order(s)", Int64(confirmationToSubmit.count)),
                    seconds: OrderHold.chosenSeconds,
                    send: {
                        isHolding = false
                        Task { await feature.confirm(confirmationToSubmit, using: operations) }
                    },
                    undo: {
                        isHolding = false
                        confirmationToSubmit = []
                    })
            } else {
                HStack(alignment: .center, spacing: 14) {
                    if correctionRequest == nil, let summary = estimate.summary {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // The order the choices make, marked by the bead, which hops when it changes.
                            InkBead(hop: summary.order.hashValue)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(summary.order)
                                    .font(DesignTokens.bodyEmphasis)
                                    .foregroundStyle(Palette.ink)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                Eyebrow(summary.place)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("review.estimate")
                    }
                    Spacer(minLength: 12)
                    Button(L10n.string("Close")) { dismiss() }
                        .buttonStyle(InkActionButtonStyle(isProminent: false))
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("review.close")
                    primaryButton
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 18)
    }

    @ViewBuilder private var primaryButton: some View {
        Group {
            if correctionRequest == nil {
                Button(estimate.action) { save() }
                    .disabled(!canSave || operations == nil)
            } else if feature.canRetryCorrection(correctionID) {
                Button(L10n.string("Try Again")) {
                    Task {
                        await feature.retryCorrection(source: source, correctionID: correctionID, using: operations)
                        if let saved = feature.corrections[correctionID]?.correction { await makePreviews(for: saved) }
                    }
                }
                .disabled(operations == nil || feature.pendingCorrections.contains(correctionID))
            } else if isChecking {
                Button(L10n.string("Checking…")) {}
                    .disabled(true)
            } else if !readyConfirmationRequests.isEmpty {
                Button(L10n.string("Review %@…", Humanize.count(readyConfirmationRequests.count, "Ready Order"))) {
                    askToConfirm()
                }
                .disabled(operations == nil || !feature.pendingCommands.isEmpty)
            } else if !hasSent {
                Button(L10n.string("Change It")) { startNewRevision() }
            }
        }
        .buttonStyle(InkActionButtonStyle())
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("review.primary")
    }

    // MARK: Actions

    private func save() {
        guard canSave else { return }
        let request = ManualCorrectionRequest(
            correctionID: correctionID,
            sourceID: source.sourceID,
            selectedAccountIDs: Array(selectedAccountIDs),
            actor: NSUserName(),
            reason: L10n.string(mode.reason),
            instructions: instructions.map(\.value)
        )
        correctionRequest = request
        Task {
            await feature.saveCorrection(source: source, request: request, using: operations)
            // Saved: go straight on to what the order would be, then ask to send what can go.
            if let saved = feature.corrections[request.correctionID]?.correction {
                await makePreviews(for: saved)
                if !readyConfirmationRequests.isEmpty { askToConfirm() }
            }
        }
    }

    private func askToConfirm() {
        confirmationToSubmit = readyConfirmationRequests
        showsConfirmation = !confirmationToSubmit.isEmpty
    }

    private func send() async {
        do {
            try await confirmOrders(Set(confirmationToSubmit.map(\.accountID)))
        } catch {
            approvalProblem = L10n.string("Nothing was sent: Touch ID was not confirmed.")
            return
        }
        approvalProblem = nil
        // Confirmed; held a few seconds in the footer so it can still be undone.
        if OrderHold.chosenSeconds > 0 {
            isHolding = true
        } else {
            await feature.confirm(confirmationToSubmit, using: operations)
        }
    }

    /// Unlocks the choices for another try under a new correction, after the engine refused.
    private func startNewRevision() {
        correctionID = UUID().uuidString.lowercased()
        correctionRequest = nil
        previewRequests = [:]
        confirmationRequests = [:]
        approvalProblem = nil
    }

    @MainActor private var confirmationSummary: String {
        confirmationToSubmit.map { request in
            let preview = feature.previews[request.previewID]
            return L10n.string(
                "%@: %@ %@ %@ at %@", request.accountID, preview?.plan?.side ?? "order",
                preview?.plan?.quantity ?? "", preview?.plan?.symbol ?? "", preview?.plan?.limitPrice ?? "—")
        }.joined(separator: "\n")
    }

    private func makePreviews(for correction: ManualCorrectionRecord) async {
        let recordedAccountIDs = Set(
            feature.corrections[correction.correctionID]?.accounts.filter { $0.status == "recorded" }.map(\.accountID) ?? [])
        for accountID in correction.selectedAccountIDs where recordedAccountIDs.contains(accountID) {
            for index in correction.instructions.indices {
                if let action = await feature.refreshPreview(
                    accountID: accountID,
                    correctionID: correction.correctionID,
                    instructionIndex: index,
                    actor: NSUserName(),
                    using: operations
                ) {
                    previewRequests["\(accountID):\(index)"] = action.preview
                    confirmationRequests[action.preview.previewID] = action.confirmation
                }
            }
        }
    }

    /// The last price of every stock any account holds, inside CopyTrading or out, by symbol.
    static func marketPrices(in accounts: [AccountOverview]) -> [String: Decimal] {
        var prices: [String: Decimal] = [:]
        for position in accounts.flatMap(\.positions) {
            if let price = position.currentPrice.flatMap({ Decimal(string: $0) }), price > 0 {
                prices[position.symbol.uppercased()] = price
            }
        }
        return prices
    }
}
