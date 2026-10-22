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

    /// What is used and out of what, as drawn: "$14 of $250".
    private var amounts: String? {
        guard let used else { return nil }
        return L10n.string(
            "%@ %@", used.formatted(.currency(code: "USD").precision(.fractionLength(0))),
            L10n.string("of %@", limit.formatted(.currency(code: "USD").precision(.fractionLength(0)))))
    }

    /// Sky while there is room, butter once it is close enough to look at, blush at the cap.
    private var tint: Color {
        fraction >= 1 ? Palette.blush : fraction >= 0.8 ? Palette.butter : Palette.sky
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
            // What is used, large, then what it is out of, quiet: "$14 of $250".
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(used?.formatted(.currency(code: "USD").precision(.fractionLength(0))) ?? "—")
                    .font(DesignTokens.statValue)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("of %@", limit.formatted(.currency(code: "USD").precision(.fractionLength(0)))))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .monospacedDigit()
            .fixedSize()
            // An ink-drawn track, filled the way a studio drawing fills one shape.
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
                // One line when it fits; otherwise each part on its own line, never a dot left
                // hanging at a line's end.
                ViewThatFits(in: .horizontal) {
                    Text(note).fixedSize()
                    Text(note.replacingOccurrences(of: " · ", with: "\n"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string(title))
        .accessibilityValue(
            used == nil
                ? L10n.string("Not read yet")
                : [amounts, L10n.string("%lld percent used", Int64((fraction * 100).rounded())), note].compactMap(\.self)
                    .reduce(into: "") { spoken, part in spoken = spoken.isEmpty ? part : L10n.string("%@, %@", spoken, part) })
    }
}
