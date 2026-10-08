import DesktopCore
import SwiftUI

struct ActivityAlerts: View {
    let feature: AccountFeatureModel
    let setup: TradingConfiguration?

    var body: some View {
        let unavailable = feature.unavailable(in: setup)
        if feature.errors["read"] != nil || !unavailable.isEmpty {
            VStack(spacing: 6) {
                if let error = feature.errors["read"] {
                    Callout(error, tone: .critical)
                        .accessibilityLabel(L10n.string("Source activity error: %@", error))
                }
                ForEach(unavailable) { gap in
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
