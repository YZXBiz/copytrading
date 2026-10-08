import DesktopCore
import SwiftUI

/// One broker account: its name, paper or live, its Alpaca keys, and the limits every order
/// into it must stay inside.
struct AccountEditorSheet: View {
    @Binding var account: TradingAccountDraft
    /// Accounts whose broker keys are already in the Keychain; a blank field keeps those.
    let savedAccountIDs: Set<String>
    let remove: () -> Void
    /// The account's latest check, when it failed and its keys are unchanged since.
    var failedCheck: TradingCapabilityCheck?
    /// Checks the account's keys with Alpaca; nil when there are none to check yet.
    var check: () async -> TradingCapabilityCheck? = { nil }
    @Environment(\.dismiss) private var dismiss
    @State private var isChecking = false

    private var hasSavedCredentials: Bool { savedAccountIDs.contains(account.name.trimmed) }

    var body: some View {
        NavigationStack {
            Form {
                SheetTitle(
                    kind: L10n.string("Alpaca account"),
                    name: account.name.trimmed.isEmpty ? L10n.string("New") : account.name.trimmed)
                Section {
                    TextField(L10n.string("Name"), text: $account.name, prompt: Text(L10n.string("e.g. %@", "primary")))
                        .accessibilityLabel(L10n.string("Account name"))
                    Picker(L10n.string("Environment"), selection: $account.environment) {
                        ForEach(TradingEnvironment.allCases, id: \.self) { environment in
                            Text(environmentTitle(environment)).tag(environment)
                        }
                    }
                    .pickerStyle(.segmented)
                    if account.environment == .live {
                        Callout(L10n.string("Live accounts place real orders with real money."), tone: .caution)
                    }
                } header: {
                    SetupSectionHeader(title: "Account", detail: "Letters, digits, “-” and “_”. Paper trades pretend money.")
                }

                Section {
                    SecureField(
                        L10n.string("API key"), text: $account.key,
                        prompt: Text(L10n.string(hasSavedCredentials ? "Leave blank to keep the saved key" : "Required"))
                    )
                    .accessibilityLabel(L10n.string("Alpaca API key"))
                    SecureField(
                        L10n.string("API secret"), text: $account.secret,
                        prompt: Text(L10n.string(hasSavedCredentials ? "Leave blank to keep the saved secret" : "Required"))
                    )
                    .accessibilityLabel(L10n.string("Alpaca API secret"))
                    if let failedCheck {
                        ConnectionCheckCallout(check: failedCheck)
                    }
                } header: {
                    SetupSectionHeader(
                        title: "Alpaca keys", detail: "Kept in your Mac's Keychain, never in the setup file.",
                        help: [SetupHelp.alpacaKeys(for: account.environment)])
                }

                Section(L10n.string("Position limits (USD)")) {
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
                        example: LimitExamples.maxAboveSignal)
                    textLimit(
                        "Maximum below signal price (%)",
                        hint:
                            "The lowest a sell can go below the guru's price. A sell that can't fill by then is cancelled.",
                        text: $account.policy.maxBelowSignalPct,
                        example: LimitExamples.maxBelowSignal)
                }

                Section(L10n.string("Timing")) {
                    numberLimit(
                        "Entries per day", hint: "The most buys in one day. Sells don't count.",
                        value: $account.policy.maxEntriesPerDay,
                        example: LimitExamples.entriesPerDay)
                    numberLimit(
                        "Maximum signal age (seconds)",
                        hint: "If a post takes longer than this to arrive, it isn't copied. You can still copy it yourself in Activity.",
                        value: $account.policy.maxSignalAgeSeconds,
                        example: LimitExamples.maxSignalAge)
                    numberLimit(
                        "Order timeout (seconds)", hint: "An order that hasn't filled by then is cancelled.",
                        value: $account.policy.orderTimeoutSeconds,
                        example: LimitExamples.orderTimeout(maxAboveSignalPct: account.policy.maxAboveSignalPct))
                }

                Section {
                    behavior(
                        "Trade in extended hours",
                        hint: L10n.string(
                            "Also copy calls %@, with limit orders.",
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
                            "Also copy calls %@. Needs extended hours on.", MarketHoursText.hours([((20, 0), (4, 0))])),
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
                } header: {
                    Text(L10n.string("Behavior"))
                } footer: {
                    Text(
                        L10n.string(
                            "CopyTrading only sells shares it bought from a guru's call. Stocks you bought yourself are never sold, even when the guru sells the same stock."
                        ))
                }

                Section {
                    Button(L10n.string("Remove Account"), role: .destructive, action: removeAccount)
                        .buttonStyle(.borderless)
                } footer: {
                    Text(L10n.string("Removing takes effect when the setup is checked and copying starts."))
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .help(L10n.string("Checking…"))
                    } else {
                        Button(L10n.string("Done"), action: finish)
                    }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 620, idealHeight: 700)
    }

    private func textLimit(_ title: String, hint: String, text: Binding<String>, example: String) -> some View {
        PolicyField(title: L10n.string(title), hint: L10n.string(hint), example: example) {
            TextField(L10n.string(title), text: text)
        }
    }

    private func numberLimit(_ title: String, hint: String, value: Binding<Int>, example: String) -> some View {
        PolicyField(title: L10n.string(title), hint: L10n.string(hint), example: example) {
            TextField(L10n.string(title), value: value, format: .number)
        }
    }

    private func numberLimit(_ title: String, hint: String, value: Binding<Double>, example: String) -> some View {
        PolicyField(title: L10n.string(title), hint: L10n.string(hint), example: example) {
            TextField(L10n.string(title), value: value, format: .number)
        }
    }

    private func behavior(_ title: String, hint: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(L10n.string(title))
            Text(L10n.string(hint))
        }
        .compactSwitch()
        // A two-line label otherwise leaves the switch announced by its value ("1, checkbox").
        .accessibilityLabel(Text(L10n.string(title)))
        .accessibilityHint(Text(L10n.string(hint)))
    }

    /// Done checks the keys with Alpaca first, and keeps the sheet open when Alpaca says no.
    private func finish() {
        Task {
            isChecking = true
            let result = await check()
            isChecking = false
            if result?.state != .failed { dismiss() }
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
