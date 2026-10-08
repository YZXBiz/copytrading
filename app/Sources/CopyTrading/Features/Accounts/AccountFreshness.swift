import DesktopCore
import SwiftUI

/// When the broker's numbers were read, that they refresh on their own, and a way to read them now.
/// Numbers older than a minute say they are not updating, and why when the engine is stopped.
struct AccountFreshness: View {
    let observedAt: String?
    let isRefreshing: Bool
    let engineStopped: Bool
    let refresh: () -> Void
    /// Under Positions, only the read time is said; the hint and button live beside Balance.
    var compact = false

    /// The app reads every account again about this often while it is open.
    static let interval = 15
    private static let staleAfter: TimeInterval = 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(spacing: 8) {
                Text(text(now: context.date))
                    .foregroundStyle(isStale(now: context.date) ? Color.orange : Palette.tertiaryInk)
                    .monospacedDigit()
                if !compact {
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button(action: refresh) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.string("Refresh"))
                        .accessibilityLabel(L10n.string("Refresh"))
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

    private func text(now: Date) -> String {
        guard let observed else { return "—" }
        let time = observed.formatted(AppTime.style(.dateTime.hour().minute().second()))
        if isStale(now: now) {
            return engineStopped
                ? L10n.string("Prices from %@, not updating: engine stopped", time)
                : L10n.string("Prices from %@, not updating", time)
        }
        if compact { return L10n.string("Prices as of %@", time) }
        return L10n.string("as of %@ · updates every %lld s", time, Int64(Self.interval))
    }
}
