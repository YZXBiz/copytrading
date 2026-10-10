import SwiftUI

/// How much of a risk limit is already used, so a limit is visible before it stops a trade.
struct LimitMeter: View {
    let title: String
    /// Nil while the account hasn't been read: the figure reads "—" and the track stays empty.
    let used: Decimal?
    let limit: Decimal
    /// One quiet line under the track, e.g. how the amount splits.
    var note: String? = nil

    private var fraction: Double {
        guard limit > 0, let used else { return 0 }
        return min(1, max(0, (used / limit).doubleValue))
    }

    private var tint: Color {
        fraction >= 1 ? .red : fraction >= 0.8 ? .orange : Palette.butter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(L10n.string(title))
            // What is used, large, then what it is out of, quiet: "$14 of $250".
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(used?.formatted(.currency(code: "USD").precision(.fractionLength(0))) ?? "—")
                    .font(DesignTokens.statValue)
                    .foregroundStyle(fraction >= 0.8 ? tint : Palette.ink)
                Text(L10n.string("of %@", limit.formatted(.currency(code: "USD").precision(.fractionLength(0)))))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .monospacedDigit()
            .fixedSize()
            // An ink-drawn track, filled the way a studio drawing fills one shape: butter while
            // there is room, orange near the cap, red at it.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().strokeBorder(Palette.ink.opacity(0.35), lineWidth: 1)
                    if fraction > 0 {
                        Capsule()
                            .fill(tint)
                            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.2))
                            .frame(width: max(8, proxy.size.width * fraction))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            if let note {
                Text(note)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string(title))
        .accessibilityValue(
            used == nil
                ? L10n.string("Not read yet")
                : [L10n.string("%lld percent used", Int64((fraction * 100).rounded())), note].compactMap(\.self).joined(
                    separator: ", "))
    }
}
