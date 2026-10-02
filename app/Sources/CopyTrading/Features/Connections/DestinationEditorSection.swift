import DesktopCore
import SwiftUI

struct DestinationEditorSection: View {
    @Binding var connection: TradingConnectionDraft
    let accountIDs: [String]
    let canRemove: Bool
    let remove: () -> Void

    private var accountChoices: [String] {
        accountIDs.contains(connection.accountID) || connection.accountID.isEmpty
            ? accountIDs
            : accountIDs + [connection.accountID]
    }

    private var policy: TradingRouteConnection {
        TradingRouteConnection(
            accountID: connection.accountID,
            mode: connection.mode,
            amountUSD: connection.amountUSD,
            defaultFraction: connection.mode == .proportional && connection.useDefaultFraction
                ? connection.defaultFraction : nil
        )
    }

    var body: some View {
        Section {
            Picker(L10n.string("Account"), selection: $connection.accountID) {
                ForEach(accountChoices, id: \.self) { accountID in
                    Text(accountID).tag(accountID)
                }
            }
            Picker(L10n.string("Sizing"), selection: $connection.mode) {
                Text(L10n.string("Fixed dollars per entry")).tag(TradingSizingMode.fixed)
                Text(L10n.string("Proportional to source")).tag(TradingSizingMode.proportional)
            }
            TextField(
                L10n.string(connection.mode == .fixed ? "Dollars per entry" : "Full position (USD)"),
                text: $connection.amountUSD
            )
            if connection.mode == .proportional {
                Toggle(L10n.string("Use a default when the source gives no fraction"), isOn: $connection.useDefaultFraction)
                if connection.useDefaultFraction {
                    TextField(
                        L10n.string("Default fraction"), text: $connection.defaultFraction,
                        prompt: Text(L10n.string("e.g. %@", "0.1666667"))
                    )
                    .accessibilityLabel(L10n.string("Default fraction"))
                }
            }
            LabeledContent(L10n.string("Sizing preview")) {
                HStack(spacing: 16) {
                    preview("1/6", budget: policy.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(6)))
                    preview("1/3", budget: policy.copiedBudgetUSD(sourceFraction: Decimal(1) / Decimal(3)))
                    preview(L10n.string("none"), budget: policy.copiedBudgetUSD(sourceFraction: nil))
                }
            }
            .help(L10n.string("Budget per entry at each source fraction, before account risk limits and price checks."))
        } header: {
            HStack {
                Text(L10n.string("Copies into"))
                Spacer()
                Button(L10n.string("Remove"), role: .destructive, action: remove)
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .disabled(!canRemove)
            }
        }
    }

    @MainActor private func preview(_ fraction: String, budget: Decimal?) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(L10n.string(budget.map(Humanize.usd) ?? "Review"))
                .monospacedDigit()
                .foregroundStyle(budget == nil ? .orange : .primary)
            Text(L10n.string("at %@", fraction))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
