import DesktopCore
import SwiftUI

/// How close each account is to its limits, and whether it is taking new entries.
struct LimitsPanel: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel
    let configuration: TradingConfiguration

    var body: some View {
        PageSection("Limits", symbol: "gauge.with.dots.needle.33percent") {
            Button(L10n.string("Accounts"), action: openAccounts)
                .buttonStyle(.link)
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(configuration.accounts) { account in
                    AccountLimits(
                        configuration: account,
                        overview: feature.accounts.first { $0.accountID == account.id }
                    )
                }
            }
        }
        .padding(18)
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                .strokeBorder(Palette.hairline, lineWidth: 0.7)
                .allowsHitTesting(false)
        }
    }

    private func openAccounts() {
        model.selectedScreen = .accounts
    }
}
