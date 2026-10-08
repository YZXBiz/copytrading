import DesktopCore
import SwiftUI

struct ValidationResultsSection: View {
    let report: TradingCapabilityReport
    /// The model name that was checked, for "has no model called …".
    var modelName = ""
    /// Puts a suggested model name into the setup.
    var useModel: (String) -> Void = { _ in }

    var body: some View {
        Section {
            ForEach(report.checks) { check in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string(check.title))
                        if let detail = detail(for: check) {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(check.state == .failed ? .red : .secondary)
                        }
                        if let suggestion = check.suggestion {
                            HStack(spacing: 8) {
                                Text(L10n.string("Did you mean “%@”?", suggestion))
                                    .font(.callout)
                                Button(L10n.string("Use %@", suggestion)) { useModel(suggestion) }
                                    .controlSize(.small)
                            }
                        }
                    }
                    Spacer(minLength: 12)
                    StatusBadge(summary(for: check.state), tone: StatusTone(check.state))
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            HStack {
                Label(L10n.string("Connection checks"), systemImage: "checklist")
                Spacer()
                StatusBadge(
                    L10n.string(report.activatable ? "Ready to start" : "Needs attention"), tone: report.activatable ? .positive : .critical
                )
            }
        } footer: {
            Text(L10n.string(report.costNotice))
        }
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
