import SwiftUI

/// How much of a risk limit is already used, so a limit is visible before it stops a trade.
struct LimitMeter: View {
    let title: String
    let used: Decimal
    let limit: Decimal
    /// One quiet line under the track, e.g. how the amount splits.
    var note: String? = nil

    private var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(1, max(0, (used / limit).doubleValue))
    }

    private var tint: Color {
        fraction >= 1 ? .red : fraction >= 0.8 ? .orange : Palette.ink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string(title))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize()
                Spacer(minLength: 8)
                Text(
                    L10n.string(
                        "%@ of %@",
                        used.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                        limit.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                )
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(fraction >= 0.8 ? tint : Palette.ink)
                .fixedSize()
            }
            .font(DesignTokens.caption)
            // A thin track that stays empty at zero, instead of a system bar with a stray dot.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.group)
                    if fraction > 0 {
                        Capsule().fill(tint).frame(width: max(4, proxy.size.width * fraction))
                    }
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string(title))
        .accessibilityValue(
            [L10n.string("%lld percent used", Int64((fraction * 100).rounded())), note].compactMap(\.self).joined(separator: ", "))
    }
}
