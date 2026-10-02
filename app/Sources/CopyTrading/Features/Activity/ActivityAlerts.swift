import SwiftUI

struct ActivityAlerts: View {
    let feature: AccountFeatureModel

    var body: some View {
        if feature.errors["read"] != nil || !feature.unavailableAccounts.isEmpty {
            VStack(spacing: 6) {
                if let error = feature.errors["read"] {
                    Callout(error, tone: .critical)
                        .accessibilityLabel(L10n.string("Source activity error: %@", error))
                }
                ForEach(feature.unavailableAccounts) { gap in
                    Callout(
                        L10n.string("Account %@ %@, so its outcomes are not shown.", gap.accountID, gap.explanation),
                        tone: .caution
                    )
                }
            }
            .padding(10)
            .background(.bar)
        }
    }
}
