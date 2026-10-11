import SwiftUI

/// A route drawn like a transit line: riso dots in ink outlines, each stop named under its dot with
/// its state. The line is solid ink while posts flow, and turns to dots after a stop that is not
/// ready, because that stop holds the posts behind it.
struct RouteLine: View {
    let stops: [RouteStop]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                VStack(spacing: 9) {
                    ZStack {
                        HStack(spacing: 0) {
                            segment(hidden: index == 0, flowing: index > 0 && flows(through: index - 1))
                            segment(hidden: index == stops.count - 1, flowing: flows(through: index))
                        }
                        ToneDot(tone: stop.tone, size: 12)
                    }
                    .frame(height: 12)
                    VStack(spacing: 2) {
                        Text(L10n.string(stop.title))
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(L10n.string(stop.state))
                            .font(DesignTokens.caption.weight(stop.needsLook ? .semibold : .regular))
                            .foregroundStyle(stop.needsLook ? Palette.ink : Palette.secondaryInk)
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

    /// Posts flow past a stop, and every stop before it, only while each of them is working.
    private func flows(through index: Int) -> Bool {
        stops[...index].allSatisfy { $0.tone == .positive }
    }

    @ViewBuilder
    private func segment(hidden: Bool, flowing: Bool) -> some View {
        if hidden {
            Color.clear.frame(height: 1.5)
        } else if flowing {
            Rectangle().fill(Palette.ink).frame(height: 1.2)
        } else {
            WritingLine()
        }
    }
}
