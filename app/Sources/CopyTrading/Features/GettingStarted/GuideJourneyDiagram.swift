import SwiftUI

/// How a post becomes a trade, drawn: one soft path across faint chart paper through six stops,
/// with the example call written under each. A chevron on each leg says which way the post
/// travels, and the last leg, the guru's sale, is dashed because it comes later. Each stop is a
/// button that chooses the card shown under the diagram; the chosen one is filled. A glowing dot
/// runs the path once when the diagram appears and again to each stop chosen, then rests: nothing
/// redraws between trips.
struct GuideJourneyDiagram: View {
    @Binding var selection: Int
    private let stops = GuideJourneyStop.all
    private let height: CGFloat = 210
    private let labelRow: CGFloat = 160
    @State private var trip: GuideJourneyTrip?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiaryInk)
                    .position(curve.point(onLeg: stops.count - 2, at: 0.45).applying(.init(translationX: 4, y: -18)))
                chevrons(curve)
                if let trip {
                    traveler(trip, on: curve)
                }
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    let isSelected = index == selection
                    node(stop, isSelected: isSelected).position(curve.point(index))
                    label(stop, number: index + 1, isSelected: isSelected)
                        .frame(width: geometry.size.width / CGFloat(stops.count))
                        .position(x: curve.point(index).x, y: labelRow)
                    Button {
                        selection = index
                    } label: {
                        Color.clear
                            .frame(width: geometry.size.width / CGFloat(stops.count), height: height)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .position(x: curve.point(index).x, y: height / 2)
                    .accessibilityLabel("\(index + 1). \(L10n.string(stop.title)): \(L10n.string(stop.example))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("guide.journey.stop.\(index + 1)")
                }
            }
        }
        .frame(height: height)
        .onAppear { travel(from: 0, to: stops.count - 2) }
        .onChange(of: selection) { old, new in travel(from: new > old ? old : 0, to: new) }
        .task(id: trip) {
            guard let trip else { return }
            try? await Task.sleep(for: .seconds(trip.seconds))
            if self.trip == trip { self.trip = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("How a post becomes a trade"))
    }

    private func travel(from: Int, to: Int) {
        guard !reduceMotion, from != to else { return }
        trip = GuideJourneyTrip(from: from, to: to)
    }

    /// The post on its way, fading in as it leaves and out as it arrives under the stop's circle.
    private func traveler(_ trip: GuideJourneyTrip, on curve: GuideJourneyCurve) -> some View {
        TimelineView(.animation) { timeline in
            let along = trip.position(at: timeline.date)
            let leg = min(max(Int(along), 0), stops.count - 2)
            let progress = trip.progress(at: timeline.date)
            Circle()
                .fill(Palette.accent)
                .frame(width: 8, height: 8)
                .shadow(color: Palette.accent.opacity(0.6), radius: 6)
                .opacity(min(1, min(progress, 1 - progress) * 10))
                .position(curve.point(onLeg: leg, at: CGFloat(along - Double(leg))))
        }
        .allowsHitTesting(false)
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

    /// One chevron on the middle of each leg, turned along the path, in the leg's own color.
    private func chevrons(_ curve: GuideJourneyCurve) -> some View {
        ForEach(0..<(stops.count - 1), id: \.self) { index in
            let isLater = index == stops.count - 2
            GuideJourneyChevron()
                .stroke(
                    legColor(index).opacity(isLater ? 0.5 : 0.9),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 5, height: 9)
                .rotationEffect(curve.direction(onLeg: index, at: 0.5))
                .position(curve.point(onLeg: index, at: 0.5))
        }
    }

    /// The path's blue turning violet, sampled at the middle of a leg.
    private func legColor(_ index: Int) -> Color {
        let mix = (Double(index) + 0.5) / Double(stops.count - 1)
        return Palette.accent.mix(with: violet, by: mix)
    }

    private func node(_ stop: GuideJourneyStop, isSelected: Bool) -> some View {
        ZStack {
            Circle().fill(isSelected ? Palette.accent : Palette.page.opacity(0.92))
            Circle().strokeBorder(Palette.ink.opacity(isSelected ? 0 : 0.08), lineWidth: 0.5)
            Image(systemName: stop.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Palette.accent)
        }
        .frame(width: 48, height: 48)
        .padding(4)
        .overlay(Circle().strokeBorder(Palette.accent.opacity(isSelected ? 0.25 : 0), lineWidth: 3))
        .shadow(color: Palette.accent.opacity(isSelected ? 0.3 : 0.12), radius: 12, y: 6)
    }

    private func label(_ stop: GuideJourneyStop, number: Int, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(number.formatted())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Text(L10n.string(stop.title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
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
