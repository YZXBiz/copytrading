import DesktopCore
import SwiftUI

/// When the broker's numbers were read, as a quiet "Updated 9:01 AM" beside them. Numbers older
/// than a minute say they stopped updating, with a butter dot and a way to read them again.
struct AccountFreshness: View {
    let observedAt: String?
    let isRefreshing: Bool
    let engineStopped: Bool
    let refresh: () -> Void

    private static let staleAfter: TimeInterval = 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let stale = isStale(now: context.date)
            HStack(spacing: 6) {
                if stale { ToneDot(tone: .caution, size: 8) }
                Text(text(stale: stale))
                    .foregroundStyle(stale ? Palette.ink : Palette.tertiaryInk)
                    .monospacedDigit()
                if stale {
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button(L10n.string("Refresh"), action: refresh)
                            .buttonStyle(QuietTextButtonStyle())
                            .accessibilityIdentifier("accounts.refresh")
                    }
                }
            }
            .font(DesignTokens.caption)
        }
    }

    private var observed: Date? { Humanize.date(observedAt) }

    private func isStale(now: Date) -> Bool {
        guard let observed else { return false }
        return now.timeIntervalSince(observed) > Self.staleAfter
    }

    private func text(stale: Bool) -> String {
        guard let observed else { return "—" }
        let time = observed.formatted(AppTime.style(.dateTime.hour().minute()))
        guard stale else { return L10n.string("Updated %@", time) }
        return engineStopped
            ? L10n.string("Not updating since %@: the engine is stopped", time)
            : L10n.string("Not updating since %@", time)
    }
}
