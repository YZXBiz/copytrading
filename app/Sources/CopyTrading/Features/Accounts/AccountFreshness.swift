import DesktopCore
import SwiftUI

/// Says so beside the numbers when the broker's numbers stop updating: after a minute without a new
/// read it shows when they were last read, with a butter dot and a way to read them again. While
/// they are current it shows nothing; the toolbar already says when everything was synced.
struct AccountFreshness: View {
    let observedAt: String?
    let isRefreshing: Bool
    let engineStopped: Bool
    let refresh: () -> Void

    private static let staleAfter: TimeInterval = 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let observed, isStale(observed, now: context.date) {
                HStack(spacing: 6) {
                    ToneDot(tone: .caution, size: 8)
                    Text(text(observed))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button(L10n.string("Refresh"), action: refresh)
                            .buttonStyle(QuietTextButtonStyle())
                            .accessibilityIdentifier("accounts.refresh")
                    }
                }
                .font(DesignTokens.caption)
            }
        }
    }

    private var observed: Date? { Humanize.date(observedAt) }

    private func isStale(_ observed: Date, now: Date) -> Bool {
        now.timeIntervalSince(observed) > Self.staleAfter
    }

    private func text(_ observed: Date) -> String {
        let time = observed.formatted(AppTime.style(.dateTime.hour().minute()))
        return engineStopped
            ? L10n.string("Not updating since %@: the engine is stopped", time)
            : L10n.string("Not updating since %@", time)
    }
}
