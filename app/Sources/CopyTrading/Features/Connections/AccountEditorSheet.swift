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

    var body: some View {
        ScrollViewReader { proxy in
            SheetScaffold(
                title: account.name.trimmed.isEmpty ? L10n.string("New Account") : account.name.trimmed,
                lede: L10n.string(account.environment == .live ? "Live · real orders, real money" : "Paper · pretend money, real prices")
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
        SheetSection(L10n.string("Account")) {
            VStack(alignment: .leading, spacing: 8) {
                SheetGroup {
                    SheetField(title: L10n.string("Name"), hint: L10n.string("Letters, digits, “-” and “_”.")) {
                        TextField(
                            L10n.string("Name"), text: $account.name,
                            prompt: Text(L10n.string("e.g. %@", "primary")).foregroundStyle(Palette.tertiaryInk)
                        )
                        .accessibilityLabel(L10n.string("Account name"))
                    }
                    SheetRow(title: L10n.string("Environment"), labelsControl: true) {
                        Picker(L10n.string("Environment"), selection: $account.environment) {
                            ForEach(TradingEnvironment.allCases, id: \.self) { environment in
                                Text(environmentTitle(environment)).tag(environment)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("account.environment")
                    }
                }
                if let problem = account.nameProblem {
                    Callout(L10n.string(problem), tone: .caution)
                        .accessibilityIdentifier("account.nameProblem")
                }
                if account.environment == .live {
                    Callout(L10n.string("Live accounts place real orders with real money."), tone: .caution)
                }
            }
        }
    }

    private var keysSection: some View {
        SheetSection(L10n.string("Alpaca keys")) {
            VStack(alignment: .leading, spacing: 8) {
                SheetGroup {
                    SheetField(title: L10n.string("API key")) {
                        SecureField(
                            L10n.string("API key"), text: $account.key,
                            prompt: Text(L10n.string(hasSavedCredentials ? "Saved" : "Required")).foregroundStyle(
                                Palette.tertiaryInk)
                        )
                        .accessibilityLabel(L10n.string("Alpaca API key"))
                    }
                    SheetField(title: L10n.string("API secret")) {
                        SecureField(
                            L10n.string("API secret"), text: $account.secret,
                            prompt: Text(L10n.string(hasSavedCredentials ? "Saved" : "Required")).foregroundStyle(
                                Palette.tertiaryInk)
                        )
                        .accessibilityLabel(L10n.string("Alpaca API secret"))
                    }
                }
                if let failedCheck {
                    ConnectionCheckCallout(check: failedCheck)
                }
            }
        } accessory: {
            HelpPopoverButton(articles: [SetupHelp.alpacaKeys(for: account.environment)])
        } footer: {
            Text(
                L10n.string(
                    hasSavedCredentials
                        ? "Kept in your Mac's Keychain. Leave blank to keep the saved keys."
                        : "Kept in your Mac's Keychain, never in the setup file."))
        }
    }

    private var limitsSection: some View {
        SheetSection(L10n.string("Position limits (USD)")) {
            SheetGroup {
                textLimit(
                    "Largest single buy", hint: "The most one buy spends, and what a call with no size buys.",
                    text: $account.policy.maxOrderUSD,
                    example: LimitExamples.maxOrder,
                    focus: .limits)
                textLimit(
                    "Maximum per stock", hint: "Shares CopyTrading bought. Your own aren't counted.",
                    text: $account.policy.maxSymbolUSD,
                    example: LimitExamples.maxSymbol)
                textLimit(
                    "Maximum total exposure", hint: "Every stock CopyTrading bought. Your own aren't counted.",
                    text: $account.policy.maxTotalUSD,
                    example: LimitExamples.maxTotal)
                textLimit(
                    "Daily loss cap", hint: "Stops buying for the day. Still sells.",
                    text: $account.policy.dailyLossCapUSD,
                    example: LimitExamples.dailyLossCap)
                textLimit(
                    "Maximum above signal price (%)", hint: "0 means never more than the guru paid.",
                    text: $account.policy.maxAboveSignalPct,
                    example: LimitExamples.maxAboveSignal,
                    focus: .entryTolerance
                )
                textLimit(
                    "Lowest sell price (% under the guru's)", hint: "A sell waits at this price or better until it fills.",
                    text: $account.policy.maxBelowSignalPct,
                    example: LimitExamples.maxBelowSignal)
            }
        } footer: {
            limitsSavedNote
        }
    }

    private var timingSection: some View {
        SheetSection(L10n.string("Timing")) {
            SheetGroup {
                numberLimit(
                    "Entries per day", hint: "Sells don't count.",
                    value: $account.policy.maxEntriesPerDay,
                    example: LimitExamples.entriesPerDay)
                numberLimit(
                    "Maximum signal age (seconds)", hint: "Older buys aren't copied. A sell always is.",
                    value: $account.policy.maxSignalAgeSeconds,
                    example: LimitExamples.maxSignalAge)
                numberLimit(
                    "Order timeout (seconds)", hint: "An unfilled buy is cancelled. A sell keeps waiting.",
                    value: $account.policy.orderTimeoutSeconds,
                    example: LimitExamples.orderTimeout(maxAboveSignalPct: account.policy.maxAboveSignalPct))
            }
        }
    }

    private var behaviorSection: some View {
        SheetSection(L10n.string("Behavior")) {
            SheetGroup {
                behavior(
                    "Trade in extended hours",
                    hint: L10n.string(
                        "%@, with limit orders.", MarketHoursText.hours([((4, 0), (9, 30)), ((16, 0), (20, 0))])),
                    isOn: $account.policy.extendedHours
                )
                // Overnight runs only with extended hours, so turning those off ends it too.
                .onChange(of: account.policy.extendedHours) { _, on in
                    if !on { account.policy.overnight = false }
                }
                behavior(
                    "Trade overnight",
                    hint: L10n.string("%@. Needs extended hours.", MarketHoursText.hours([((20, 0), (4, 0))])),
                    isOn: $account.policy.overnight
                )
                .onChange(of: account.policy.overnight) { _, on in
                    if on { account.policy.extendedHours = true }
                }
                behavior(
                    "Copy exits", hint: "Off means you sell copied shares yourself.",
                    isOn: $account.policy.copyExits)
                behavior(
                    "Ask me before sending orders", hint: "Each order waits for your Touch ID.",
                    isOn: $account.policy.approveOrders)
                SheetRow(
                    title: L10n.string("After a restart"),
                    hint: L10n.string(
                        account.policy.recoveryPreference == .automatic
                            ? "Buys again once its checks pass."
                            : "Buys wait for your Start Copying."),
                    labelsControl: true
                ) {
                    Picker(L10n.string("After a restart"), selection: $account.policy.recoveryPreference) {
                        ForEach(RecoveryPreference.allCases, id: \.self) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("account.recovery")
                }
            }
        } footer: {
            Text(L10n.string("Only shares CopyTrading bought are ever sold. Your own shares are never touched."))
        }
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
    /// A limit's value: a number field, its digits at the trailing edge.
    /// A hidden-label field still needs its name for VoiceOver, which `labelsHidden` drops, and the
    /// row's name is kept from VoiceOver, so the field carries it.
    fileprivate func limitField(_ label: String) -> some View {
        accessibilityLabel(label)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .sheetInput(width: DesignTokens.sheetNumberWidth)
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
