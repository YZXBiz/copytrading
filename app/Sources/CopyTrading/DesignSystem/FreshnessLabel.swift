import SwiftUI

/// Answers "are these numbers current?" wherever money is shown, ticking once a second.
struct FreshnessLabel: View {
    let updatedAt: Date?
    let isCopying: Bool
    var compact = false

    /// Numbers older than this while copying are called out rather than trusted silently.
    static let staleAfter: TimeInterval = 90

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = state(at: context.date)
            HStack(spacing: 6) {
                Circle()
                    .fill(state.color)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(compact ? state.shortText : state.text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(state.text)
        }
        .fixedSize()
    }

    private func state(at now: Date) -> (text: String, shortText: String, color: Color) {
        guard let updatedAt else {
            return (
                isCopying ? L10n.string("Waiting for the first update") : L10n.string("Not copying"),
                isCopying ? L10n.string("Waiting for update") : L10n.string("Not copying"), .secondary
            )
        }
        let age = max(0, now.timeIntervalSince(updatedAt))
        let ago = Self.ago(age)
        if !isCopying { return (L10n.string("Synced %@", ago), L10n.string("Synced %@", ago), .secondary) }
        if age > Self.staleAfter {
            return (L10n.string("Updates delayed · last %@", ago), L10n.string("Delayed · %@", ago), .orange)
        }
        return (L10n.string("Synced %@", ago), L10n.string("Synced %@", ago), .green)
    }

    static func ago(_ seconds: TimeInterval) -> String {
        if seconds < 5 { return L10n.string("just now") }
        if seconds < 60 { return L10n.string("%llds ago", Int64(seconds)) }
        if seconds < 3600 { return L10n.string("%lld min ago", Int64(seconds / 60)) }
        return L10n.string("%lld h ago", Int64(seconds / 3600))
    }
}
