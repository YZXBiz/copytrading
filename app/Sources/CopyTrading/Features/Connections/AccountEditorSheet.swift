import DesktopCore
import SwiftUI

/// One broker account: its name, paper or live, its Alpaca keys, and the limits every order
/// into it must stay inside.
struct AccountEditorSheet: View {
    @Binding var account: TradingAccountDraft
    /// Accounts whose broker keys are already in the Keychain; a blank field keeps those.
    let savedAccountIDs: Set<String>
    let remove: () -> Void
    /// Opens scrolled to one setting with its field focused: the limits, or the price tolerance.
    var focus: AccountEditorFocus?
    /// The account's latest check, when it failed and its keys are unchanged since.
    var failedCheck: TradingCapabilityCheck?
    /// Checks the account's keys with Alpaca; nil when there are none to check yet.
    var check: () async -> TradingCapabilityCheck? = { nil }
    /// Saves the account's limits at once when they are all that changed: nil when more changed,
    /// otherwise whether they were saved.
    var saveLimits: () async -> Bool? = { nil }
    /// Why the limits weren't saved, when they weren't.
    var limitsError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var isChecking = false
    /// nil until limits are saved or refused; then whether they were saved.
    @State private var limitsSaved: Bool?
    /// Alpaca refused the keys on this sheet's last Done and they haven't changed since.
    @State private var keysRefused = false
    @FocusState private var focusedField: AccountEditorFocus?
    @State private var confirmsRemove = false

    private var hasSavedCredentials: Bool { savedAccountIDs.contains(account.name.trimmed) }

    /// The account at a glance: paper or live, whether its keys are in, and its two main limits.
    private var facts: [SheetFact] {
        let money = { (text: String) -> String? in
            Decimal(string: text.trimmed).map { $0.formatted(.currency(code: "USD").precision(.fractionLength(0...2))) }
        }
        var facts = [
            account.environment == .live
                ? SheetFact(symbol: "bolt.fill", text: L10n.string("Live · real money"), tint: Palette.blush)
                : SheetFact(brand: "alpaca", text: L10n.string("Paper · pretend money"), tint: Palette.sky),
            hasSavedCredentials || (!account.key.isEmpty && !account.secret.isEmpty)
                ? SheetFact(symbol: "key.fill", text: L10n.string("Keys in Keychain"), tint: Palette.sage)
                : SheetFact(symbol: "key", text: L10n.string("Keys needed"), tint: Palette.butter),
        ]
        switch (money(account.policy.maxOrderUSD), money(account.policy.maxSymbolUSD)) {
        case let (order?, stock?):
            facts.append(SheetFact(symbol: "cart", text: L10n.string("%@ per order · %@ per stock", order, stock)))
        case let (order?, nil):
            facts.append(SheetFact(symbol: "cart", text: L10n.string("%@ per order", order)))
        case let (nil, stock?):
            facts.append(SheetFact(symbol: "cart", text: L10n.string("%@ per stock", stock)))
        case (nil, nil):
            break
        }
        return facts
    }

    var body: some View {
        ScrollViewReader { proxy in
            SheetScaffold(
                kind: L10n.string("Alpaca account"),
                title: account.name.trimmed.isEmpty ? L10n.string("New") : account.name.trimmed,
                lede: L10n.string(account.environment == .live ? "Live · real orders, real money" : "Paper · pretend money, real prices"),
                facts: facts
            ) {
                accountSection
                keysSection
                limitsSection
                timingSection
                behaviorSection
            } leading: {
                Button(L10n.string("Remove Account…"), role: .destructive) { confirmsRemove = true }
                    .buttonStyle(SheetQuietButtonStyle(isDestructive: true))
                    .confirmationDialog(
                        L10n.string("Remove %@?", account.name.trimmed.isEmpty ? L10n.string("this account") : account.name.trimmed),
                        isPresented: $confirmsRemove
                    ) {
                        Button(L10n.string("Remove Account"), role: .destructive, action: removeAccount)
                        Button(L10n.string("Keep"), role: .cancel) {}
                    } message: {
                        Text(
                            L10n.string(
                                "Its guru stops being copied once you start copying with this change. Shares in it stay with Alpaca."))
                    }
            } actions: {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .help(L10n.string("Checking…"))
                }
                Button(L10n.string("Done"), action: finish)
                    .buttonStyle(SheetButtonStyle(isPrimary: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isChecking)
            }
            // Return in a limit field saves it, as Done does.
            .onSubmit(commitLimits)
            .onChange(of: account.policy) { limitsSaved = nil }
            .onChange(of: [account.key, account.secret, account.name]) { keysRefused = false }
            .onChange(of: account.environment) { keysRefused = false }
            .task {
                guard let focus else { return }
                // After the sheet settles, so the scroll lands and the field takes focus.
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation { proxy.scrollTo(focus, anchor: focus == .limits ? .top : .center) }
                focusedField = focus
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 620, idealHeight: 720)
    }

    private var accountSection: some View {
        SheetSection(L10n.string("Account"), detail: L10n.string("Letters, digits, “-” and “_”.")) {
            SheetField(title: L10n.string("Name")) {
                TextField(
                    L10n.string("Name"), text: $account.name,
                    prompt: Text(L10n.string("e.g. %@", "primary")).foregroundStyle(Palette.tertiaryInk)
                )
                .accessibilityLabel(L10n.string("Account name"))
            }
            if let problem = account.nameProblem {
                Callout(L10n.string(problem), tone: .caution)
                    .accessibilityIdentifier("account.nameProblem")
            }
            SheetChoices(
                label: L10n.string("Environment"),
                choices: TradingEnvironment.allCases.map { ($0, environmentTitle($0)) },
                selection: $account.environment, identifier: "account.environment"
            )
            .padding(.vertical, 14)
            if account.environment == .live {
                Callout(L10n.string("Live accounts place real orders with real money."), tone: .caution)
            }
        }
        .icon(brand: "alpaca")
        .mark(account.name.trimmed.isEmpty || account.nameProblem != nil ? .needsYou : .done)
    }

    private var keysSection: some View {
        SheetSection(L10n.string("Alpaca keys"), detail: L10n.string("Kept in your Mac's Keychain, never in the setup file.")) {
            SheetField(title: L10n.string("API key")) {
                SecureField(
                    L10n.string("API key"), text: $account.key,
                    prompt: Text(L10n.string(hasSavedCredentials ? "Leave blank to keep the saved key" : "Required")).foregroundStyle(
                        Palette.tertiaryInk)
                )
                .accessibilityLabel(L10n.string("Alpaca API key"))
            }
            SheetField(title: L10n.string("API secret")) {
                SecureField(
                    L10n.string("API secret"), text: $account.secret,
                    prompt: Text(L10n.string(hasSavedCredentials ? "Leave blank to keep the saved secret" : "Required")).foregroundStyle(
                        Palette.tertiaryInk)
                )
                .accessibilityLabel(L10n.string("Alpaca API secret"))
            }
            if let failedCheck {
                ConnectionCheckCallout(check: failedCheck)
            }
        } accessory: {
            HelpPopoverButton(articles: [SetupHelp.alpacaKeys(for: account.environment)])
        }
        .icon(symbol: "key")
        .mark(hasSavedCredentials || (!account.key.isEmpty && !account.secret.isEmpty) ? .done : .needsYou)
    }

    private var limitsSection: some View {
        SheetSection(L10n.string("Position limits (USD)")) {
            textLimit(
                "Maximum per order", hint: "The most one buy can spend. A bigger buy is made smaller.",
                text: $account.policy.maxOrderUSD,
                example: LimitExamples.maxOrder,
                focus: .limits)
            textLimit(
                "Maximum per stock",
                hint:
                    "The most this account can hold in one stock, including shares you bought yourself. It's also the guru's full position. A buy that would go over is skipped.",
                text: $account.policy.maxSymbolUSD,
                example: LimitExamples.maxSymbol)
            textLimit(
                "Maximum total exposure",
                hint:
                    "The most this account can hold in all stocks, including your own. A buy that would go over is skipped.",
                text: $account.policy.maxTotalUSD,
                example: LimitExamples.maxTotal)
            textLimit(
                "Daily loss cap",
                hint: "If the account is down this much today, it stops buying until tomorrow. It still sells.",
                text: $account.policy.dailyLossCapUSD,
                example: LimitExamples.dailyLossCap)
            textLimit(
                "Maximum above signal price (%)",
                hint:
                    "The most a buy can pay above the guru's price. 0 means never more than the guru paid.",
                text: $account.policy.maxAboveSignalPct,
                example: LimitExamples.maxAboveSignal,
                focus: .entryTolerance
            )
            textLimit(
                "Maximum below signal price (%)",
                hint:
                    "The lowest a sell can go below the guru's price. A sell that can't fill by then is cancelled.",
                text: $account.policy.maxBelowSignalPct,
                example: LimitExamples.maxBelowSignal)
        } footer: {
            limitsSavedNote
        }
        .icon(symbol: "dollarsign.circle")
    }

    private var timingSection: some View {
        SheetSection(L10n.string("Timing")) {
            numberLimit(
                "Entries per day", hint: "The most buys in one day. Sells don't count.",
                value: $account.policy.maxEntriesPerDay,
                example: LimitExamples.entriesPerDay)
            numberLimit(
                "Maximum signal age (seconds)",
                hint:
                    "If a post takes longer than this to arrive, it isn't copied. You can still copy it yourself in Activity.",
                value: $account.policy.maxSignalAgeSeconds,
                example: LimitExamples.maxSignalAge)
            numberLimit(
                "Order timeout (seconds)", hint: "An order that hasn't filled by then is cancelled.",
                value: $account.policy.orderTimeoutSeconds,
                example: LimitExamples.orderTimeout(maxAboveSignalPct: account.policy.maxAboveSignalPct))
        }
        .icon(symbol: "clock")
    }

    private var behaviorSection: some View {
        SheetSection(L10n.string("Behavior")) {
            behavior(
                "Trade in extended hours",
                hint: L10n.string(
                    "Also copy calls before and after regular hours, %@, with limit orders.",
                    MarketHoursText.hours([((4, 0), (9, 30)), ((16, 0), (20, 0))])),
                isOn: $account.policy.extendedHours
            )
            // Overnight runs only with extended hours, so turning those off ends it too.
            .onChange(of: account.policy.extendedHours) { _, on in
                if !on { account.policy.overnight = false }
            }
            behavior(
                "Trade overnight",
                hint: L10n.string(
                    "Also copy calls overnight, %@. Needs extended hours on.", MarketHoursText.hours([((20, 0), (4, 0))])),
                isOn: $account.policy.overnight
            )
            .onChange(of: account.policy.overnight) { _, on in
                if on { account.policy.extendedHours = true }
            }
            behavior(
                "Copy exits", hint: "Sell when the guru sells. Off means you sell copied shares yourself.",
                isOn: $account.policy.copyExits)
            behavior(
                "Ask me before sending orders",
                hint: "Nothing is sent by itself. Each order waits on the account's page until you approve it with Touch ID.",
                isOn: $account.policy.approveOrders)
        } footer: {
            Text(
                L10n.string(
                    "CopyTrading only sells shares it bought from a guru's call. Stocks you bought yourself are never sold, even when the guru sells the same stock."
                ))
        }
        .icon(symbol: "switch.2")
    }

    /// Limits saved without a check say so where they were typed.
    @ViewBuilder private var limitsSavedNote: some View {
        switch limitsSaved {
        case true?:
            Label(L10n.string("Saved · applies to the next order"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(StatusTone.positive.color)
                .accessibilityIdentifier("account.limitsSaved")
        case false?:
            Callout(limitsError ?? L10n.string("These limits weren't saved."), tone: .caution)
        case nil:
            EmptyView()
        }
    }

    private func commitLimits() {
        Task { limitsSaved = await saveLimits() }
    }

    private func textLimit(
        _ title: String, hint: String, text: Binding<String>, example: String, focus: AccountEditorFocus? = nil
    ) -> some View {
        SheetRow(title: L10n.string(title), hint: L10n.string(hint), example: example, labelsControl: true) {
            if let focus {
                TextField(L10n.string(title), text: text)
                    .focused($focusedField, equals: focus)
                    .limitField(L10n.string(title))
                    .id(focus)
            } else {
                TextField(L10n.string(title), text: text).limitField(L10n.string(title))
            }
        }
    }

    private func numberLimit(_ title: String, hint: String, value: Binding<Int>, example: String) -> some View {
        SheetRow(title: L10n.string(title), hint: L10n.string(hint), example: example, labelsControl: true) {
            TextField(L10n.string(title), value: value, format: .number).limitField(L10n.string(title))
        }
    }

    private func numberLimit(_ title: String, hint: String, value: Binding<Double>, example: String) -> some View {
        SheetRow(title: L10n.string(title), hint: L10n.string(hint), example: example, labelsControl: true) {
            TextField(L10n.string(title), value: value, format: .number).limitField(L10n.string(title))
        }
    }

    private func behavior(_ title: String, hint: String, isOn: Binding<Bool>) -> some View {
        SheetRow(title: L10n.string(title), hint: L10n.string(hint), labelsControl: true) {
            Toggle(L10n.string(title), isOn: isOn)
                .labelsHidden()
                .compactSwitch()
                .accessibilityHint(Text(L10n.string(hint)))
        }
    }

    /// Done checks the keys with Alpaca first, and keeps the sheet open when Alpaca says no.
    /// Changed limits, when they are all that changed, are saved then and copied with at once;
    /// the sheet stays open when they can't be.
    private func finish() {
        // Limits refused once, or keys Alpaca refused and still unchanged, close on a second Done:
        // the account stays in the setup, and its row says it couldn't connect.
        if limitsSaved == false || keysRefused {
            dismiss()
            return
        }
        Task {
            isChecking = true
            let result = await check()
            guard result?.state != .failed else {
                isChecking = false
                keysRefused = true
                return
            }
            limitsSaved = await saveLimits()
            isChecking = false
            if limitsSaved != false { dismiss() }
        }
    }

    private func removeAccount() {
        dismiss()
        remove()
    }

    @MainActor private func environmentTitle(_ environment: TradingEnvironment) -> String {
        switch environment {
        case .paper: L10n.string("Paper")
        case .live: L10n.string("Live")
        }
    }
}

extension View {
    /// A limit's value: a short field in a soft well, its number at the trailing edge.
    /// A hidden-label field still needs its name for VoiceOver, which `labelsHidden` drops, and the
    /// row's name is kept from VoiceOver, so the field carries it.
    fileprivate func limitField(_ label: String) -> some View {
        labelsHidden()
            .accessibilityLabel(label)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.well, in: .rect(cornerRadius: 8))
            .frame(width: 120)
    }
}

#if DEBUG
    #Preview("Account: zhap-account-2") {
        @Previewable @State var account: TradingAccountDraft = {
            var policy = TradingAccountPolicy()
            policy.maxOrderUSD = "250"
            policy.maxSymbolUSD = "1000"
            policy.maxTotalUSD = "3000"
            policy.dailyLossCapUSD = "250"
            policy.maxSignalAgeSeconds = 600
            return TradingAccountDraft(name: "zhap-account-2", environment: .paper, policy: policy, savedName: "zhap-account-2")
        }()
        AccountEditorSheet(account: $account, savedAccountIDs: ["zhap-account-2"], remove: {})
            .frame(width: 600, height: 900)
    }
#endif
