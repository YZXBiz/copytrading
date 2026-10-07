import SwiftUI

/// How a post becomes a trade, drawn: one soft path across faint chart paper through six stops,
/// with the example call written under each. A dot carries the post along the path from the
/// guru's channel to Activity; the last leg, the guru's sale, is dashed because it comes later.
struct GuideJourneyDiagram: View {
    private let stops = GuideJourneyStop.all
    private let height: CGFloat = 210
    private let labelRow: CGFloat = 160
    /// Seconds for the dot to travel from the post to Activity.
    private let journeySeconds = 6.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var violet: Color { Color(red: 0.55, green: 0.42, blue: 0.95) }

    var body: some View {
        GeometryReader { geometry in
            let curve = GuideJourneyCurve(width: geometry.size.width, count: stops.count)
            ZStack(alignment: .topLeading) {
                ChartPaperBackdrop(focus: .center, gridSpacing: 18, paper: false)
                    .mask {
                        RadialGradient(colors: [.black, .clear], center: .center, startRadius: 60, endRadius: geometry.size.width / 2)
                    }
                glow(width: geometry.size.width)
                path(curve)
                Text(L10n.string("later"))
                    .font(.system(size: 10.5, design: .serif).italic())
                    .foregroundStyle(Palette.tertiaryInk)
                    .position(curve.point(onLeg: stops.count - 2, at: 0.45).applying(.init(translationX: 4, y: -18)))
                traveler(curve)
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    node(stop).position(curve.point(index))
                    label(stop, number: index + 1)
                        .frame(width: geometry.size.width / CGFloat(stops.count))
                        .position(x: curve.point(index).x, y: labelRow)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("How a post becomes a trade"))
        .accessibilityValue(
            stops.enumerated().map { "\($0.offset + 1). \(L10n.string($0.element.title)): \(L10n.string($0.element.example))" }
                .joined(separator: ". "))
    }

    private func glow(width: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [Palette.accent.opacity(colorScheme == .dark ? 0.16 : 0.10), violet.opacity(0.05), .clear],
                    center: .center, startRadius: 10, endRadius: width / 2)
            )
            .frame(width: width, height: 190)
            .position(x: width / 2, y: 80)
            .blur(radius: 20)
            .allowsHitTesting(false)
    }

    private func path(_ curve: GuideJourneyCurve) -> some View {
        ForEach(0..<(stops.count - 1), id: \.self) { index in
            let (a, c1, c2, b) = curve.controls(index)
            Path { path in
                path.move(to: a)
                path.addCurve(to: b, control1: c1, control2: c2)
            }
            .stroke(
                LinearGradient(colors: [Palette.accent.opacity(0.55), violet.opacity(0.55)], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: index == stops.count - 2 ? [2, 6] : []))
        }
    }

    /// The post, travelling from the guru's channel to Activity and fading in and out at the ends.
    /// With Reduce Motion it rests on the way to the AI.
    private func traveler(_ curve: GuideJourneyCurve) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let legs = stops.count - 2
            let progress =
                reduceMotion
                ? 0.15 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: journeySeconds) / journeySeconds
            let along = progress * Double(legs)
            let leg = min(Int(along), legs - 1)
            Circle()
                .fill(Palette.accent)
                .frame(width: 8, height: 8)
                .shadow(color: Palette.accent.opacity(0.6), radius: 6)
                .opacity(reduceMotion ? 1 : min(1, min(progress, 1 - progress) * 12))
                .position(curve.point(onLeg: leg, at: CGFloat(along - Double(leg))))
        }
    }

    private func node(_ stop: GuideJourneyStop) -> some View {
        ZStack {
            // Solid paper, not a material: a material re-blurs whatever moves behind it every frame.
            Circle().fill(Palette.page.opacity(0.92))
            Circle().strokeBorder(Palette.ink.opacity(0.08), lineWidth: 0.5)
            Image(systemName: stop.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.accent)
        }
        .frame(width: 48, height: 48)
        .shadow(color: Palette.accent.opacity(0.12), radius: 12, y: 6)
    }

    private func label(_ stop: GuideJourneyStop, number: Int) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(number.formatted())
                    .font(.system(size: 12, weight: .medium, design: .serif).italic())
                    .foregroundStyle(Palette.accent)
                Text(L10n.string(stop.title))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            Text(L10n.string(stop.example))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Palette.page.opacity(0.7), in: .capsule)
                .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.07), lineWidth: 0.5))
        }
    }
}
