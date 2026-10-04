import DesktopCore
import SwiftUI

/// Why a connection didn't check out, in words, with the closest model name to use when the one
/// typed doesn't exist.
struct ConnectionCheckCallout: View {
    let check: TradingCapabilityCheck
    var modelName = ""
    var useModel: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Callout(ConnectionProblem.text(for: check, modelName: modelName), tone: .caution)
                .accessibilityIdentifier("connections.problem")
            if let suggestion = check.suggestion, let useModel {
                Button(L10n.string("Use %@", suggestion)) { useModel(suggestion) }
                    .controlSize(.small)
                    .accessibilityIdentifier("connections.useSuggestion")
            }
        }
        .transition(.opacity)
    }
}
