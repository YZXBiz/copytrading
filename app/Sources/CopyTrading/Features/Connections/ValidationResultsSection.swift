import DesktopCore
import SwiftUI

struct ValidationResultsSection: View {
    let report: TradingCapabilityReport

    var body: some View {
        Section {
            ForEach(report.checks) { check in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string(check.title))
                        if let detail = detail(for: check) {
                            Text(L10n.string(detail))
                                .font(.callout)
                                .foregroundStyle(check.state == .failed ? .red : .secondary)
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
        var parts: [String] = []
        if let identity = check.identity { parts.append(L10n.string("Verified as %@", identity)) }
        if let reason = check.reasonCode { parts.append(Humanize.code(reason)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
