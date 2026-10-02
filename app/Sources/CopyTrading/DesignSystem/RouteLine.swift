import SwiftUI

/// A route drawn like a transit line: a thin rule through small dots, each stop named under
/// its dot with its state. A dot is filled once the stop is working, hollow while it waits.
struct RouteLine: View {
    let stops: [RouteStop]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                VStack(spacing: 9) {
                    ZStack {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(index == 0 ? .clear : Palette.hairline)
                            Rectangle()
                                .fill(index == stops.count - 1 ? .clear : Palette.hairline)
                        }
                        .frame(height: 1.5)
                        dot(stop.tone)
                    }
                    .frame(height: 12)
                    VStack(spacing: 2) {
                        Text(L10n.string(stop.title))
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(L10n.string(stop.state))
                            .font(DesignTokens.caption)
                            .foregroundStyle(stop.tone == .caution || stop.tone == .critical ? stop.tone.color : Palette.secondaryInk)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.string("%@, %@", L10n.string(stop.title), L10n.string(stop.state)))
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func dot(_ tone: StatusTone) -> some View {
        if tone == .inactive {
            Circle()
                .strokeBorder(Palette.tertiaryInk.opacity(0.6), lineWidth: 1.5)
                .background(Circle().fill(Palette.page))
                .frame(width: 11, height: 11)
        } else {
            Circle()
                .fill(tone.color)
                .frame(width: 11, height: 11)
                .background(Circle().fill(tone.color.opacity(0.18)).frame(width: 21, height: 21))
        }
    }
}
