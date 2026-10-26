import SwiftUI

/// Your limit, where the market was, and the guru's own price, drawn on one ink line so the gaps
/// between them read at a glance: a tick for your limit, a dot for the market or the fill, a fine
/// grey tick for the guru's price, and the difference between your limit and the market over them.
struct PriceRuler: View {
    let points: PricePoints

    /// Captions closer than this push apart, each toward its own side.
    private static let captionGap: CGFloat = 112
    /// How far a caption's centre stays from either end, so its words never leave the ruler.
    private static let captionInset: CGFloat = 52

    private var gapFraction: Double {
        guard points.limit != 0 else { return 0 }
        return ((points.market - points.limit) / points.limit).doubleValue
    }

    /// Past the limit is the wrong side: above it for a buy, below it for a sell.
    private var isPast: Bool { points.buying ? points.market > points.limit : points.market < points.limit }

    /// The limit's name: a buy's most it pays, a sell's lowest price.
    private var limitLabel: String { L10n.string(points.buying ? "Your limit" : "Lowest sell price") }

    /// The gap in plain words: "3.9% over your limit" for a buy, "0.4% above your lowest price" for
    /// a sell, or for a few cents, "1¢ under your limit". A sell's market above its floor is good
    /// news, so it never reads as over a limit.
    private var gapText: String? {
        let gap = points.market - points.limit
        guard gap != 0 else { return L10n.string(points.buying ? "At your limit" : "At your lowest price") }
        let amount: String
        if abs(gapFraction) < 0.001 {
            let cents = (abs(gap) * 100).doubleValue.rounded()
            amount = cents < 100 ? "\(Int(cents))¢" : abs(gap).formatted(.currency(code: "USD"))
        } else {
            amount = abs(gapFraction).formatted(.percent.precision(.fractionLength(1)))
        }
        // Each side is one phrase around the amount, so Chinese can put the amount after the verb.
        if points.buying {
            return L10n.string(gap > 0 ? "%@ over your limit" : "%@ under your limit", amount)
        }
        return L10n.string(gap > 0 ? "%@ above your lowest price" : "%@ under your lowest price", amount)
    }

    /// The marks in the order they are drawn: the guru's price when it differs, your limit, then
    /// where the market was.
    private var marks: [Mark] {
        var marks: [Mark] = []
        if let guru = points.guru, guru != points.limit {
            marks.append(Mark(kind: .guru, label: L10n.string("Guru's price"), value: guru))
        }
        marks.append(Mark(kind: .limit, label: limitLabel, value: points.limit))
        marks.append(Mark(kind: .market, label: points.marketLabel, value: points.market))
        return marks
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let marks = self.marks
            // At least two percent of the price either side, so a cent looks like a cent.
            let values = marks.map(\.value)
            let lowest = values.min() ?? points.limit
            let highest = values.max() ?? points.limit
            let middle = (lowest + highest) / 2
            let half = max((highest - lowest) / 2 * 1.25, middle * 0.02)
            let low = middle - half
            let span = max((half * 2).doubleValue, 0.000_001)
            let x: (Decimal) -> CGFloat = { CGFloat((($0 - low).doubleValue) / span) * width }
            let limitX = x(points.limit)
            let marketX = x(points.market)
            let captions = Self.captionCentres(marks.map { x($0.value) }, width: width)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 34))
                    path.addLine(to: CGPoint(x: width, y: 34))
                }
                .stroke(Palette.hairline, style: InkStroke.style)
                // A market past the limit is the gap that held the order, filled the way a studio
                // drawing fills one shape; a market on the right side of it is no miss to fill.
                if isPast {
                    Capsule()
                        .fill(Palette.butter)
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: InkStroke.width))
                        .frame(width: max(abs(marketX - limitX), 6), height: 12)
                        .position(x: (limitX + marketX) / 2, y: 34)
                }
                ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                    tick(mark.kind)
                        .position(x: x(mark.value), y: 34)
                    caption(mark, at: captions[index])
                }
                if let gapText {
                    Text(gapText)
                        .font(DesignTokens.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isPast ? Palette.ink : Palette.secondaryInk)
                        .fixedSize()
                        .position(x: min(max((limitX + marketX) / 2, Self.captionInset * 1.6), width - Self.captionInset * 1.6), y: 12)
                }
            }
        }
        .frame(height: 80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func tick(_ kind: Mark.Kind) -> some View {
        switch kind {
        case .guru:
            Rectangle()
                .fill(Palette.tertiaryInk)
                .frame(width: 1.2, height: 12)
        case .limit:
            Rectangle()
                .fill(Palette.ink)
                .frame(width: InkStroke.width, height: 18)
        case .market:
            Circle()
                .fill(Palette.ink)
                .frame(width: 11, height: 11)
        }
    }

    private func caption(_ mark: Mark, at x: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(mark.label)
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
            Text(money(mark.value))
                .font(DesignTokens.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(mark.kind == .guru ? Palette.secondaryInk : Palette.ink)
        }
        .lineLimit(1)
        .fixedSize()
        .position(x: x, y: 63)
    }

    /// Each caption under its own mark, pushed apart just enough that none overlaps the next and
    /// held inside the ruler.
    static func captionCentres(_ marks: [CGFloat], width: CGFloat) -> [CGFloat] {
        let order = marks.indices.sorted { marks[$0] < marks[$1] }
        var centres = order.map { marks[$0] }
        let lowest = captionInset
        let highest = max(width - captionInset, lowest)
        for index in centres.indices {
            centres[index] = min(max(centres[index], lowest), highest)
            if index > 0 { centres[index] = max(centres[index], centres[index - 1] + captionGap) }
        }
        for index in centres.indices.reversed() {
            centres[index] = min(centres[index], index == centres.count - 1 ? highest : centres[index + 1] - captionGap)
        }
        for index in centres.indices {
            centres[index] = max(centres[index], index == 0 ? lowest : centres[index - 1] + 1)
        }
        // Spread both ways about the marks rather than all to one side, still inside the ruler.
        let sorted = order.map { marks[$0] }
        var shift = zip(centres, sorted).map { $0 - $1 }.reduce(0, +) / CGFloat(max(centres.count, 1))
        if let first = centres.first, first - shift < lowest { shift = first - lowest }
        if let last = centres.last, last - shift > highest { shift = last - highest }
        centres = centres.map { $0 - shift }
        var placed = marks
        for (rank, index) in order.enumerated() { placed[index] = centres[rank] }
        return placed
    }

    private var accessibilityText: String {
        let read = L10n.string(
            "%@ %@, %@ %@", limitLabel, money(points.limit), points.marketLabel.lowercased(), money(points.market))
        guard let guru = points.guru, guru != points.limit else { return read }
        return L10n.string(
            "%@, %@", read, L10n.string("%@ %@", L10n.string("Guru's price").lowercased(), money(guru)))
    }

    private func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private struct Mark {
        enum Kind { case guru, limit, market }
        let kind: Kind
        let label: String
        let value: Decimal
    }
}
