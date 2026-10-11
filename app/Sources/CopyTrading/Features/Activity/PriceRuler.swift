import SwiftUI

/// Your limit and where the market was, drawn on one ink line so the gap between them reads at a
/// glance: a tick for your limit, a dot for the market or the fill, and the difference over them.
struct PriceRuler: View {
    let points: PricePoints

    private var gapFraction: Double {
        guard points.limit != 0 else { return 0 }
        return ((points.market - points.limit) / points.limit).doubleValue
    }

    /// Past the limit is the wrong side: above it for a buy, below it for a sell.
    private var isPast: Bool { points.buying ? points.market > points.limit : points.market < points.limit }

    /// The gap in plain words: "+3.9% over your limit", or for a few cents, "1¢ under your limit".
    private var gapText: String? {
        let gap = points.market - points.limit
        guard gap != 0 else { return L10n.string("At your limit") }
        let side = L10n.string(gap > 0 ? "over your limit" : "under your limit")
        if abs(gapFraction) < 0.001 {
            let cents = (abs(gap) * 100).doubleValue.rounded()
            return L10n.string("%@ %@", cents < 100 ? "\(Int(cents))¢" : abs(gap).formatted(.currency(code: "USD")), side)
        }
        return L10n.string("%@ %@", abs(gapFraction).formatted(.percent.precision(.fractionLength(1))), side)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // At least two percent of the price either side, so a cent looks like a cent.
            let middle = (points.limit + points.market) / 2
            let half = max(abs(points.market - points.limit) * 0.8, middle * 0.02)
            let low = middle - half
            let span = max((half * 2).doubleValue, 0.000_001)
            let x: (Decimal) -> CGFloat = { CGFloat((($0 - low).doubleValue) / span) * width }
            let limitX = x(points.limit)
            let marketX = x(points.market)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 34))
                    path.addLine(to: CGPoint(x: width, y: 34))
                }
                .stroke(Palette.hairline, style: InkStroke.style)
                // The gap that decided the order, filled the way a studio drawing fills one shape.
                Capsule()
                    .fill(Palette.butter)
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: InkStroke.width))
                    .frame(width: max(abs(marketX - limitX), 6), height: 12)
                    .position(x: (limitX + marketX) / 2, y: 34)
                Rectangle()
                    .fill(Palette.ink)
                    .frame(width: InkStroke.width, height: 16)
                    .position(x: limitX, y: 34)
                Circle()
                    .fill(Palette.ink)
                    .frame(width: 11, height: 11)
                    .position(x: marketX, y: 34)
                if let gapText {
                    Text(gapText)
                        .font(DesignTokens.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isPast ? Palette.ink : Palette.secondaryInk)
                        .fixedSize()
                        .position(x: (limitX + marketX) / 2, y: 14)
                }
                // Close prices push their captions apart, each toward its own side.
                let close = abs(limitX - marketX) < 110
                let spread: CGFloat = close ? 56 : 0
                let limitLeads = limitX <= marketX
                caption(L10n.string("Your limit"), points.limit, at: limitX + (limitLeads ? -spread : spread), in: width)
                caption(points.marketLabel, points.market, at: marketX + (limitLeads ? spread : -spread), in: width)
            }
        }
        .frame(height: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.string(
                "Your limit %@, %@ %@", money(points.limit), points.marketLabel.lowercased(), money(points.market)))
    }

    private func caption(_ label: String, _ value: Decimal, at x: CGFloat, in width: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(DesignTokens.eyebrow)
                .tracking(DesignTokens.eyebrowTracking)
                .foregroundStyle(Palette.tertiaryInk)
            Text(money(value))
                .font(DesignTokens.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .fixedSize()
        .position(x: min(max(x, 44), width - 44), y: 60)
    }

    private func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
