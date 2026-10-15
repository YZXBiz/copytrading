import DesktopCore
import SwiftUI

struct ValidationResultsSection: View {
    let report: TradingCapabilityReport
    /// The model name that was checked, for "has no model called …".
    var modelName = ""
    /// Puts a suggested model name into the setup.
    var useModel: (String) -> Void = { _ in }
    /// Accounts with a page to open: the saved ones.
    var accountPages: Set<String> = []
    /// Opens an account's page, where what it holds can be sold.
    var openAccount: (String) -> Void = { _ in }
    /// Puts a removed account back in the setup, as it was saved.
    var keepAccount: (String) -> Void = { _ in }

    var body: some View {
        SheetSection(L10n.string("Connection checks")) {
            ForEach(report.checks) { check in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CapabilityCheckTitle.text(for: check))
                            .font(DesignTokens.rowTitle)
                            .foregroundStyle(Palette.ink)
                        if let detail = detail(for: check) {
                            Text(detail)
                                .font(DesignTokens.caption)
                                .foregroundStyle(check.state == .failed ? StatusTone.critical.color : Palette.tertiaryInk)
                        }
                        if let account = removedAccount(check) {
                            HStack(spacing: 16) {
                                if accountPages.contains(account), check.reasonCode != "removed_account_unreadable" {
                                    Button(L10n.string("Open %@", account)) { openAccount(account) }
                                        .accessibilityIdentifier("setupCheck.openAccount.\(account)")
                                }
                                Button(L10n.string("Keep %@", account)) { keepAccount(account) }
                                    .accessibilityIdentifier("setupCheck.keepAccount.\(account)")
                            }
                            .buttonStyle(SheetQuietButtonStyle())
                            .padding(.top, 4)
                        }
                        if let suggestion = check.suggestion {
                            HStack(spacing: 8) {
                                Text(L10n.string("Did you mean “%@”?", suggestion))
                                    .font(DesignTokens.caption)
                                Button(L10n.string("Use %@", suggestion)) { useModel(suggestion) }
                                    .buttonStyle(SheetQuietButtonStyle())
                                    .font(DesignTokens.caption)
                            }
                        }
                    }
                    Spacer(minLength: 12)
                    StatusBadge(summary(for: check.state), tone: StatusTone(check.state))
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        } accessory: {
            StatusBadge(
                L10n.string(report.activatable ? "Ready to start" : "Needs attention"), tone: report.activatable ? .positive : .critical
            )
        } footer: {
            Text(L10n.string(report.costNotice))
        }
    }

    /// The saved account a failed setup check says still holds something, so it can be opened
    /// or kept.
    private func removedAccount(_ check: TradingCapabilityCheck) -> String? {
        guard check.name == .configuration, check.state == .failed,
            check.reasonCode?.hasPrefix("removed_account_") == true
        else { return nil }
        return check.subject
    }

    /// What a check found, in words: never the engine's raw identity string.
    private func detail(for check: TradingCapabilityCheck) -> String? {
        if check.state == .failed { return ConnectionProblem.text(for: check, modelName: modelName) }
        guard check.state == .ready, let identity = check.identity else { return nil }
        switch check.name {
        case .source:
            return L10n.string("Signed in to Discord")
        case .model:
            let parts = identity.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let provider = TradingProviderName(rawValue: parts[0])?.title ?? parts[0]
            return L10n.string("%@ answered as %@", provider, parts[1])
        case .broker:
            return L10n.string(check.environment == .live ? "Alpaca live account found" : "Alpaca paper account found")
        case .notification, .configuration:
            return nil
        }
    }

    @MainActor private func summary(for state: TradingCapabilityState) -> String {
        switch state {
        case .ready: L10n.string("Ready")
        case .failed: L10n.string("Needs attention")
        case .notConfigured: L10n.string("Not configured")
        }
    }
}
