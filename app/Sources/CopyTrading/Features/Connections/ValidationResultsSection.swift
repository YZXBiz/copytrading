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
            ForEach(report.releaseGates, id: \.self) { gate in
                Callout(L10n.string("Release gate: %@", Humanize.code(gate)), tone: .caution)
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

    private func detail(for check: TradingCapabilityCheck) -> String? {
        if check.name == .model, let explanation = modelProblem(check) { return explanation }
        var parts: [String] = []
        if let identity = check.identity { parts.append(L10n.string("Verified as %@", identity)) }
        if let reason = check.reasonCode { parts.append(L10n.string(Humanize.code(reason))) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What went wrong with the interpreter, in words: the key, the model name, or the answer.
    private func modelProblem(_ check: TradingCapabilityCheck) -> String? {
        let service = TradingProviderName(rawValue: check.adapter)?.title ?? check.adapter
        switch check.reasonCode {
        case "model_key_rejected":
            return L10n.string("%@ didn't accept the API key.", service)
        case "model_not_found":
            return L10n.string("%@ has no model called “%@”.", service, modelName.trimmingCharacters(in: .whitespaces))
        case "model_probe_rejected":
            return L10n.string("The model answered, but couldn't read a test post. Try another model.")
        case "model_auth_or_probe_failed":
            return L10n.string("Couldn't reach %@. Check the API key and your connection.", service)
        default:
            return nil
        }
    }

    @MainActor private func summary(for state: TradingCapabilityState) -> String {
        switch state {
        case .ready: L10n.string("Ready")
        case .failed: L10n.string("Needs attention")
        case .notConfigured: L10n.string("Not configured")
        case .unsupported: L10n.string("Unsupported")
        }
    }
}
