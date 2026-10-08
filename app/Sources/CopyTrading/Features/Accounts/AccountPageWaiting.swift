import DesktopCore
import SwiftUI

/// An account in the setup that the engine has not read yet: its name, and why its numbers are
/// still to come.
struct AccountPageWaiting: View {
    let accountID: String
    let configuration: TradingAccountConfiguration?
    let model: AppModel
    let feature: AccountFeatureModel

    private var reason: String {
        if let gap = feature.unavailable(in: model.savedTradingConfiguration).first(where: { $0.accountID == accountID }) {
            return L10n.string("Account %@ %@, so its data is not shown.", gap.accountID, gap.explanation)
        }
        if model.runtimeState == .stopped || model.runtimeState == .failed {
            return L10n.string("The engine is stopped. The balance appears once it runs and the broker has been read.")
        }
        return L10n.string("The balance appears once copying is on and the broker has been read.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(accountID)
                    .font(DesignTokens.entityTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let configuration {
                    AccountModeBadge(environment: configuration.environment)
                }
            }
            if let error = feature.errors["read"] {
                Callout(error, tone: .critical)
                    .accessibilityLabel(L10n.string("Account data error: %@", error))
            }
            HStack(spacing: 12) {
                if feature.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "hourglass")
                        .foregroundStyle(Palette.tertiaryInk)
                        .accessibilityHidden(true)
                }
                Text(reason)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .font(DesignTokens.bodyText)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(.horizontal, 16)
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                    .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .accessibilityHidden(true)
            }
        }
    }
}
