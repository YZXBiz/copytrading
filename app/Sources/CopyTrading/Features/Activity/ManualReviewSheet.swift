import DesktopCore
import SwiftUI

/// The owner says what a post should do and sends it: the post in its own group, then each trade's
/// rows (Buy or Sell, the stock, how much, the price) and the accounts, and a bar that always shows
/// the order it makes and one button. Underneath it is the engine's manual correction: saved,
/// previewed fresh in each account, then confirmed (ADR-0007).
struct ManualReviewSheet: View {
    let source: SourceActivity
    let accounts: [AccountOverview]
    let operations: (any ManualReviewOperations)?
    let feature: ManualReviewFeatureModel
    let guruName: String?
    /// This guru's full position in each account it copies to, by account.
    let connections: [String: TradingRouteConnection]
    /// Each account's largest single buy, which caps any one buy.
    let maxOrderUSD: [String: Decimal]
    /// How far above the price each account's buy limit sits, in percent.
    let maxAbovePct: [String: Decimal]
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
    /// The broker's latest quote for each stock in the trades, by symbol.
    @State private var quotes: [String: LiveQuote] = [:]
    /// Stocks whose quote is being asked for.
    @State private var refreshingQuotes: Set<String> = []
    /// The quotes were asked for once already, as the sheet opened.
    @State private var hasAskedForQuotes = false

    init(
        source: SourceActivity,
        copying: WaitingCall? = nil,
        accounts: [AccountOverview],
        operations: (any ManualReviewOperations)?,
        feature: ManualReviewFeatureModel,
        guruName: String? = nil,
        connections: [TradingRouteConnection] = [],
        maxOrderUSD: [String: Decimal] = [:],
        maxAbovePct: [String: Decimal] = [:],
        confirmOrders: @escaping (Set<String>) async throws -> Void,
        engineStopped: Bool = false,
        startEngine: @escaping () -> Void = {}
    ) {
        self.source = source
        // An account can copy only a post it received: the guru's calls reach the one account it
        // copies into, so another account has nothing to place them against.
        let reached = Set(source.destinations.map(\.accountID))
        self.accounts = reached.isEmpty ? accounts : accounts.filter { reached.contains($0.accountID) }
        self.operations = operations
        self.feature = feature
        self.guruName = guruName
        self.connections = Dictionary(connections.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })
        self.maxOrderUSD = maxOrderUSD
        self.maxAbovePct = maxAbovePct
        self.confirmOrders = confirmOrders
        self.engineStopped = engineStopped
        self.startEngine = startEngine
        mode = ManualReviewMode(copying: copying)
        let available = Set(self.accounts.map(\.accountID))
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
        // A post's price is copied as a limit at that price; a buy with none follows the live ask
        // once the quote the sheet asks for on opening answers.
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
        ManualOrderEstimate(
            drafts: instructions, accounts: chosenAccounts, connections: connections, maxOrderUSD: maxOrderUSD,
            maxAbovePct: maxAbovePct, mode: mode, quotes: quotes,
            planned: previewRequests.compactMapValues { request in
                Decimal(engine: feature.previews[request.previewID]?.plan?.budgetUSD)
            })
    }

    /// The account whose read keys quote the stocks: the first chosen, else the first listed.
    private var quotingAccountID: String? { (chosenAccounts.first ?? accounts.first)?.accountID }

    /// What to quote: the stocks typed so far through one account; a change starts a new ask.
    private var quoteRequest: [String] {
        let symbols = Set(instructions.map { $0.symbol.trimmed.uppercased() }.filter(LiveQuote.canQuote))
        return [quotingAccountID ?? ""] + symbols.sorted()
    }

    private var isChecking: Bool {
        feature.pendingCorrections.contains(correctionID) || !feature.pendingPreviews.isEmpty
    }

    /// An order may have gone. A refusal, or an order the broker turned down, leaves the call open
    /// to review again.
    private var hasSent: Bool {
        confirmationRequests.values.contains { request in
            guard let outcome = feature.commandOutcomes[request.commandID] else { return false }
            if let result = outcome.result { return !["rejected", "broker_rejected"].contains(result.status) }
            return outcome.error == "confirm_failed"
        }
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
        SheetScaffold(title: L10n.string(mode.title), lede: lede) {
            if engineStopped || engineDisconnected {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Callout(L10n.string("CopyTrading's engine isn't running, so this can't be saved or placed yet."), tone: .caution)
                    Button(L10n.string("Start Engine"), action: startEngine)
                        .buttonStyle(SheetButtonStyle())
                }
            }
            postSection
            trades
            accountChoices
            if correctionRequest != nil { results }
            ManualReviewHistory(source: source, feature: feature, operations: operations)
        } leading: {
            if isHolding {
                OrderHold(
                    title: orderCount("Placing 1 order", "Placing %lld orders"),
                    seconds: OrderHold.chosenSeconds,
                    send: {
                        isHolding = false
                        Task { await feature.confirm(confirmationToSubmit, using: operations) }
                    },
                    undo: {
                        isHolding = false
                        confirmationToSubmit = []
                    })
            } else if correctionRequest == nil, let summary = estimate.summary {
                // Wrapped, never cut off: the order is what the owner is about to send.
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.order)
                        .font(DesignTokens.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.string("%@ · checks your limits first", summary.place))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("review.estimate")
            }
        } actions: {
            if !isHolding {
                // The buttons keep their whole labels; the summary beside them wraps instead.
                Button(L10n.string("Close")) { dismiss() }
                    .buttonStyle(SheetButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("review.close")
                    .fixedSize()
                primaryButton
                    .fixedSize()
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 600, idealHeight: 780)
        .confirmationDialog(
            L10n.string("Confirm manual orders?"),
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button(orderCount("Confirm 1 order", "Confirm %lld orders"), role: .destructive) {
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
        .task(id: quoteRequest) { await followQuotes() }
        .onDisappear { feature.clearPrivateEvidence() }
    }

    /// The post the trade comes from, in its own group.
    private var postSection: some View {
        SheetSection(L10n.string("Post")) {
            SheetGroup {
                let text = source.readableText()
                Text(text.isEmpty ? L10n.string("A post with no words") : text)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("review.post")
            }
        }
    }

    /// Who posted, when, and why the sheet is open, on one quiet line.
    @MainActor private var lede: String {
        [guruName, Humanize.postTime(source.sourceAt), L10n.string(why)].compactMap { $0 }.joined(separator: " · ")
    }

    private var why: String {
        switch mode {
        case .approve: "Waiting for your approval."
        case .copy: "Waiting for you to copy it."
        case .enter:
            guessed
                ? "Filled in from the post's words. Check it, then send."
                : "CopyTrading couldn't read a trade in this post."
        }
    }

    /// Each trade in its own section, "Trade 2" with Remove when there are several.
    private var trades: some View {
        VStack(alignment: .leading, spacing: DesignTokens.sheetSectionSpacing) {
            let holdings = ManualHolding.holdings(in: accounts, accountIDs: selectedAccountIDs)
            let single = chosenAccounts.count == 1 ? chosenAccounts.first.flatMap { connections[$0.accountID] } : nil
            let cap = chosenAccounts.count == 1 ? chosenAccounts.first.flatMap { maxOrderUSD[$0.accountID] } : nil
            ForEach($instructions) { $instruction in
                let index = instructions.firstIndex { $0.id == instruction.id } ?? 0
                SheetSection(
                    instructions.count > 1 ? L10n.string("Trade %lld", Int64(index + 1)) : L10n.string("Trade")
                ) {
                    ManualInstructionEditor(
                        draft: $instruction,
                        holdings: holdings,
                        quote: quotes[instruction.symbol.trimmed.uppercased()],
                        refreshQuote: refreshingQuotes.contains(instruction.symbol.trimmed.uppercased())
                            ? nil : { refreshQuote(instruction.symbol.trimmed.uppercased()) },
                        fullPosition: single,
                        maxOrderUSD: cap
                    )
                } accessory: {
                    if instructions.count > 1 {
                        Button(L10n.string("Remove")) { instructions.removeAll { $0.id == instruction.id } }
                            .buttonStyle(SheetQuietButtonStyle(isDestructive: true))
                    }
                }
            }
            if correctionRequest == nil, instructions.count < 20 {
                Button(L10n.string("Add Trade"), systemImage: "plus") {
                    instructions.append(ManualInstructionDraft())
                }
                .buttonStyle(SheetQuietButtonStyle())
                .accessibilityIdentifier("review.addTrade")
            }
        }
        .disabled(correctionRequest != nil)
    }

    private var accountChoices: some View {
        SheetSection(L10n.string("Accounts")) {
            SheetGroup {
                if accounts.isEmpty {
                    SheetRow(title: L10n.string("No account status is loaded"), isReading: true) { EmptyView() }
                }
                ForEach(accounts) { account in
                    SheetRow(
                        title: account.accountID, hint: account.environment == .live ? L10n.string("Live") : nil,
                        labelsControl: true
                    ) {
                        Toggle(
                            account.accountID,
                            isOn: Binding(
                                get: { selectedAccountIDs.contains(account.accountID) },
                                set: { on in
                                    if on {
                                        selectedAccountIDs.insert(account.accountID)
                                    } else {
                                        selectedAccountIDs.remove(account.accountID)
                                    }
                                })
                        )
                        .labelsHidden()
                        .compactSwitch()
                        .accessibilityLabel(Text(account.accountID))
                        .accessibilityIdentifier("review.account.\(account.accountID)")
                    }
                }
            }
            .disabled(correctionRequest != nil)
        }
    }

    // MARK: After saving

    private var results: some View {
        SheetSection(L10n.string("Checked just now")) {
            VStack(alignment: .leading, spacing: 12) {
                if let correctionRequest, let error = feature.errors[correctionRequest.correctionID] {
                    Callout(ManualRefusalText.line(error), tone: .critical)
                        .accessibilityLabel(L10n.string("Correction error: %@", ManualRefusalText.line(error)))
                }
                if let saved = correctionRequest.flatMap({ feature.corrections[$0.correctionID] }) {
                    ForEach(saved.accounts.filter { $0.status != "recorded" }) { result in
                        // The account, then why it did not save and what to do, in one line.
                        Callout(
                            L10n.string("%@: %@", result.accountID, ManualRefusalText.reason(result.reason ?? result.status)),
                            tone: result.status == "unavailable" ? .caution : .critical)
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
        .buttonStyle(SheetButtonStyle(isPrimary: true))
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

    /// "Confirm 1 order" or "Confirm 3 orders", by how many are about to go.
    @MainActor private func orderCount(_ one: String, _ many: String) -> String {
        let count = confirmationToSubmit.count
        return count == 1 ? L10n.string(one) : L10n.string(many, Int64(count))
    }

    /// Each order exactly as the engine planned it: a buy by the dollars it spends after the max
    /// per order and its shares at the limit, a sell by its shares.
    @MainActor private var confirmationSummary: String {
        confirmationToSubmit.compactMap { request in
            guard let plan = feature.previews[request.previewID]?.plan else { return nil }
            let shares = Decimal(engine: plan.quantity).map { Humanize.shares($0) } ?? plan.quantity
            let limit = Decimal(engine: plan.limitPrice).map(Humanize.usd) ?? "—"
            if let budget = Decimal(engine: plan.budgetUSD) {
                return L10n.string(
                    "%@: Buy %@ of %@, %@ at %@ or less", request.accountID, Humanize.dollars("\(budget)"), plan.symbol,
                    shares, limit)
            }
            let side = L10n.string(plan.side.lowercased() == "sell" ? "Sell" : "Buy")
            return L10n.string("%@: %@ %@ of %@ at %@", request.accountID, side, shares, plan.symbol, limit)
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

    /// How often an open sheet asks again, so Market always reads a live price.
    private static let quoteRefresh = Duration.seconds(30)

    /// Asks the engine for each stock's quote as the sheet opens, again every `quoteRefresh` while
    /// it stays open, and after a typed ticker settles; read-only. A failed ask keeps the last
    /// quote, which then says how old it is.
    private func followQuotes() async {
        guard let operations, let accountID = quotingAccountID else { return }
        let symbols = Array(quoteRequest.dropFirst())
        // The ask as the sheet opens goes out at once; a ticker being typed waits for a pause.
        if hasAskedForQuotes {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        }
        hasAskedForQuotes = true
        while !Task.isCancelled {
            for symbol in symbols {
                refreshingQuotes.insert(symbol)
                defer { refreshingQuotes.remove(symbol) }
                let quote: MarketQuote?
                do {
                    quote = try await operations.quote(accountID: accountID, symbol: symbol)
                } catch {
                    if Task.isCancelled { return }
                    continue
                }
                quotes[symbol] = LiveQuote(symbol: symbol, quote: quote)
            }
            do { try await Task.sleep(for: Self.quoteRefresh) } catch { return }
        }
    }

    /// Asks the broker for one stock's quote again, now. A failed ask keeps the last one.
    private func refreshQuote(_ symbol: String) {
        guard let operations, let accountID = quotingAccountID, !refreshingQuotes.contains(symbol) else { return }
        refreshingQuotes.insert(symbol)
        Task {
            defer { refreshingQuotes.remove(symbol) }
            guard let quote = try? await operations.quote(accountID: accountID, symbol: symbol) else { return }
            quotes[symbol] = LiveQuote(symbol: symbol, quote: quote)
        }
    }
}

#if DEBUG
    #Preview("Enter Trade") {
        let source = try! JSONDecoder().decode(
            SourceActivity.self,
            from: Data(
                """
                {"sequence":1,"source_id":"discord:1:2","source_revision":1,"source_at":"2026-10-21T14:30:00Z",\
                "captured_at":"2026-10-21T14:30:00Z","text":"12.13加了6分之一常规仓f","capture_status":"delivered",\
                "parse_status":"complete","delivery_status":"delivered","decision":"no_trade","parser_reason":"x",\
                "parser_profile":"stock-reading-v3","interpreted_by":"deepseek-flash","instructions":[],"suggested":[],\
                "destinations":[],\
                "source_event":{"event_type":"discord_message","content":"12.13加了6分之一常规仓f","embeds":[],"attachments":[],"attachments_omitted":0,"capture_status":"complete","payload_bytes":30}}
                """.utf8))
        return ManualReviewSheet(
            source: source, accounts: [], operations: nil, feature: ManualReviewFeatureModel(), guruName: "Zhao",
            confirmOrders: { _ in })
    }
#endif
