import DesktopCore
import SwiftUI

/// The menu bar item itself, readable without opening it: the mark, today's change across the
/// accounts being copied ("+$12", "−$15"), how many calls wait for the owner ("· 2 waiting"), and
/// how many accounts stopped on their own ("· 1 stopped", with a warning mark instead of the
/// usual one). While locked, or before any account has a balance, it is the mark alone.
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
        return accountFeature.knownActivity.count {
            WaitingCall.open($0, skipped: model.skippedCalls.contains($0.sourceID), now: now) != nil
        }
    }

    private var stopped: Int {
        guard model.isTradingUnlocked else { return 0 }
        return accountFeature.accounts.count(where: CopyingState.isStopped)
    }

    var body: some View {
        // The status item draws one image and one line of text; the text carries everything.
        Label {
            Text(title)
        } icon: {
            Image(systemName: stopped > 0 ? "exclamationmark.triangle.fill" : "arrow.triangle.branch")
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
        if stopped > 0 {
            parts.append(L10n.string("%lld stopped", Int64(stopped)))
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        title.isEmpty ? "CopyTrading" : L10n.string("CopyTrading, %@", title)
    }
}
