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
        return L10n.string("The balance appears once the broker has been read.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // The same name and grey mode line as a read account, so the page does not change shape
            // when the numbers arrive.
            VStack(alignment: .leading, spacing: 8) {
                Text(accountID)
                    .font(DesignTokens.entityTitle)
                    .tracking(DesignTokens.entityTitleTracking)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                if let configuration {
                    Text(L10n.string(configuration.environment == .live ? "Live" : "Paper"))
                        .foregroundStyle(configuration.environment == .live ? Color.orange : Palette.tertiaryInk)
                        .font(DesignTokens.lede)
                        .tracking(DesignTokens.ledeTracking)
                }
            }
            if let error = feature.errors["read"] {
                Callout(error, tone: .critical)
                    .accessibilityLabel(L10n.string("Account data error: %@", error))
            }
            // One sentence on the ground line, as every empty section reads; no dashed frame.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if feature.isRefreshing {
                        ProgressView().controlSize(.mini)
                    }
                    Text(reason)
                        .font(DesignTokens.bodyText)
                        .tracking(0.3)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                InkGround()
            }
            .accessibilityElement(children: .combine)
        }
    }
}
