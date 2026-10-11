import SwiftUI

/// How a post becomes a trade, drawn in one ink line through six ringed stops, with the example
/// call written under each. A chevron on each leg says which way the post travels, and the last
/// leg, the guru's sale, is dashed because it comes later. Each stop is a button that chooses the
/// note shown under the diagram; the chosen one is filled with ink. A dot runs the path once when
/// the diagram appears and again to each stop chosen, then rests: nothing redraws between trips.
struct GuideJourneyDiagram: View {
    @Binding var selection: Int
    private let stops = GuideJourneyStop.all
    private let height: CGFloat = 210
    private let labelRow: CGFloat = 160
    @State private var trip: GuideJourneyTrip?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let curve = GuideJourneyCurve(width: geometry.size.width, count: stops.count)
            ZStack(alignment: .topLeading) {
                path(curve)
                Text(L10n.string("later").uppercased())
                    .font(DesignTokens.eyebrow)
                    .tracking(DesignTokens.eyebrowTracking)
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
                .fill(Palette.ink)
                .frame(width: 7, height: 7)
                .opacity(min(1, min(progress, 1 - progress) * 10))
                .position(curve.point(onLeg: leg, at: CGFloat(along - Double(leg))))
        }
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
                index == stops.count - 2 ? Palette.tertiaryInk : Palette.ink,
                style: StrokeStyle(lineWidth: InkStroke.style.lineWidth, lineCap: .round, dash: index == stops.count - 2 ? [2, 6] : []))
        }
    }

    /// One chevron on the middle of each leg, turned along the path.
    private func chevrons(_ curve: GuideJourneyCurve) -> some View {
        ForEach(0..<(stops.count - 1), id: \.self) { index in
            let isLater = index == stops.count - 2
            GuideJourneyChevron()
                .stroke(
                    isLater ? Palette.tertiaryInk : Palette.ink,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 5, height: 9)
                .rotationEffect(curve.direction(onLeg: index, at: 0.5))
                .position(curve.point(onLeg: index, at: 0.5))
        }
    }

    private func node(_ stop: GuideJourneyStop, isSelected: Bool) -> some View {
        ZStack {
            Circle().fill(isSelected ? Palette.ink : Palette.page)
            Circle().strokeBorder(Palette.ink, lineWidth: InkStroke.style.lineWidth)
            Image(systemName: stop.symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isSelected ? Palette.page : Palette.ink)
        }
        .frame(width: 46, height: 46)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isSelected)
    }

    private func label(_ stop: GuideJourneyStop, number: Int, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%02d", number))
                    .font(DesignTokens.eyebrow)
                    .tracking(DesignTokens.eyebrowTracking)
                    .foregroundStyle(Palette.tertiaryInk)
                Text(L10n.string(stop.title))
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
            }
            Text(L10n.string(stop.example))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
        }
    }
}
