import DesktopCore
import SwiftUI

/// The menu bar item itself, readable without opening it: the mark, today's change across the
/// accounts being copied ("+$12", "−$15"), and how many calls wait for the owner ("· 2 waiting").
/// While locked, or before any account has a balance, it is the mark alone.
struct MenuBarGlance: View {
    let model: AppModel
    let accountFeature: AccountFeatureModel

    private var change: Decimal? {
        let balances = accountFeature.accounts.filter(\.activeConfiguration).compactMap(\.balance)
        guard model.isTradingUnlocked, !balances.isEmpty else { return nil }
        return balances.compactMap { Decimal(engine: $0.dayChangeUSD) }.reduce(0, +)
    }

    private var waiting: Int {
        guard model.isTradingUnlocked else { return 0 }
        let now = Date.now
        return accountFeature.activity.compactMap(WaitingCall.init).filter {
            !$0.hasExpired(at: now) && !model.skippedCalls.contains($0.source.sourceID)
        }.count
    }

    var body: some View {
        // The status item draws one image and one line of text; the text carries everything.
        Label {
            Text(title)
        } icon: {
            Image(systemName: "arrow.triangle.branch")
        }
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(accessibilityText)
    }

    private var title: String {
        var parts: [String] = []
        if let change {
            let money = change.magnitude.formatted(.currency(code: "USD").precision(.fractionLength(0)))
            parts.append(change < 0 ? "−\(money)" : "+\(money)")
        }
        if waiting > 0 {
            parts.append(L10n.string("%lld waiting", Int64(waiting)))
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        title.isEmpty ? "CopyTrading" : L10n.string("CopyTrading, %@", title)
    }
}
