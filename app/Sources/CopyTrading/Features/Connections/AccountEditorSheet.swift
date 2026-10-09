import DesktopCore
import SwiftUI

/// One broker account: its name, paper or live, its Alpaca keys, and the limits every order
/// into it must stay inside.
struct AccountEditorSheet: View {
    @Binding var account: TradingAccountDraft
    /// Accounts whose broker keys are already in the Keychain; a blank field keeps those.
    let savedAccountIDs: Set<String>
    let remove: () -> Void
    /// Opens on Maximum above signal price, scrolled to it with the field focused.
    var focusesEntryTolerance = false
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
    @FocusState private var entryToleranceFocused: Bool

    private var hasSavedCredentials: Bool { savedAccountIDs.contains(account.name.trimmed) }

    var body: some View {
        ScrollViewReader { proxy in
            SheetScaffold(
                kind: L10n.string("Alpaca account"),
                title: account.name.trimmed.isEmpty ? L10n.string("New") : account.name.trimmed,
                lede: L10n.string(account.environment == .live ? "Live · real orders, real money" : "Paper · pretend money, real prices")
            ) {
                accountSection
                keysSection
                limitsSection
                timingSection
                behaviorSection
            } leading: {
                Button(L10n.string("Remove Account"), role: .destructive, action: removeAccount)
                    .buttonStyle(SheetQuietButtonStyle(isDestructive: true))
                    .help(L10n.string("Removing takes effect when the setup is checked and copying starts."))
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
            .task {
                guard focusesEntryTolerance else { return }
                // After the sheet settles, so the scroll lands and the field takes focus.
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation { proxy.scrollTo(Self.entryToleranceRow, anchor: .center) }
                entryToleranceFocused = true
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 620, idealHeight: 720)
    }

    private var accountSection: some View {
        SheetSection(L10n.string("Account"), detail: L10n.string("Letters, digits, “-” and “_”. Paper trades pretend money.")) {
            SheetField(title: L10n.string("Name")) {
                TextField(
                    L10n.string("Name"), text: $account.name,
                    prompt: Text(L10n.string("e.g. %@", "primary")).foregroundStyle(Palette.tertiaryInk)
                )
                .accessibilityLabel(L10n.string("Account name"))
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
    }

    private var limitsSection: some View {
        SheetSection(L10n.string("Position limits (USD)")) {
            textLimit(
                "Maximum per order", hint: "The most one buy can spend. A bigger buy is made smaller.",
                text: $account.policy.maxOrderUSD,
                example: LimitExamples.maxOrder)
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
                focus: $entryToleranceFocused
            )
            .id(Self.entryToleranceRow)
            textLimit(
                "Maximum below signal price (%)",
                hint:
                    "The lowest a sell can go below the guru's price. A sell that can't fill by then is cancelled.",
                text: $account.policy.maxBelowSignalPct,
                example: LimitExamples.maxBelowSignal)
        } footer: {
            limitsSavedNote
        }
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
                hint: "Nothing is sent by itself. Each order waits in Activity until you approve it with Touch ID.",
                isOn: $account.policy.approveOrders)
        } footer: {
            Text(
                L10n.string(
                    "CopyTrading only sells shares it bought from a guru's call. Stocks you bought yourself are never sold, even when the guru sells the same stock."
                ))
        }
    }

    private static let entryToleranceRow = "maxAboveSignalPct"

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
        _ title: String, hint: String, text: Binding<String>, example: String, focus: FocusState<Bool>.Binding? = nil
    ) -> some View {
        SheetRow(title: L10n.string(title), hint: L10n.string(hint), example: example) {
            Group {
                if let focus {
                    TextField(L10n.string(title), text: text).focused(focus)
                } else {
                    TextField(L10n.string(title), text: text)
                }
            }
            .limitField()
        }
    }

    private func numberLimit(_ title: String, hint: String, value: Binding<Int>, example: String) -> some View {
        SheetRow(title: L10n.string(title), hint: L10n.string(hint), example: example) {
            TextField(L10n.string(title), value: value, format: .number).limitField()
        }
    }

    private func numberLimit(_ title: String, hint: String, value: Binding<Double>, example: String) -> some View {
        SheetRow(title: L10n.string(title), hint: L10n.string(hint), example: example) {
            TextField(L10n.string(title), value: value, format: .number).limitField()
        }
    }

    private func behavior(_ title: String, hint: String, isOn: Binding<Bool>) -> some View {
        SheetRow(title: L10n.string(title), hint: L10n.string(hint)) {
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
        // Limits refused once close on a second Done and wait for the full check.
        if limitsSaved == false {
            dismiss()
            return
        }
        Task {
            isChecking = true
            let result = await check()
            guard result?.state != .failed else {
                isChecking = false
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
    /// A limit's value: a short underlined field, its number at the trailing edge.
    fileprivate func limitField() -> some View {
        labelsHidden()
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .underlineField()
            .frame(width: 110)
    }
}
