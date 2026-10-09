import SwiftUI

/// What a position cost against what it is worth now, drawn as a small ruler like the Activity
/// card's: an ink tick at the average cost in the middle, a dot at today's price, and the gap
/// between them filled green above cost or red below it. Every row shares one scale (a fifth of the
/// cost either side), so a long gap means a big move; the two prices sit under it in figures.
struct PositionCostMark: View {
    let cost: Decimal
    let price: Decimal

    static let width: CGFloat = 156
    /// The move that reaches the ruler's end: 20% either side of cost.
    private static let reach = 0.2

    private var change: Double {
        guard cost != 0 else { return 0 }
        return ((price - cost) / cost).doubleValue
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let half = proxy.size.width / 2 - 6
                let middle = proxy.size.width / 2
                let priceX = middle + half * CGFloat(min(max(change / Self.reach, -1), 1))
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 7))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 7))
                    }
                    .stroke(Palette.hairline, style: InkStroke.style)
                    if abs(priceX - middle) >= 1 {
                        Capsule()
                            .fill(ChangeDirection(price - cost).color)
                            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.2))
                            .frame(width: max(abs(priceX - middle), 6), height: 8)
                            .position(x: (priceX + middle) / 2, y: 7)
                    }
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: InkStroke.width, height: 14)
                        .position(x: middle, y: 7)
                    Circle()
                        .fill(Palette.ink)
                        .frame(width: 8, height: 8)
                        .position(x: priceX, y: 7)
                }
            }
            .frame(height: 14)
            HStack(spacing: 4) {
                Text(cost, format: .currency(code: "USD"))
                    .foregroundStyle(Palette.tertiaryInk)
                Image(systemName: "arrow.right")
                    .imageScale(.small)
                    .foregroundStyle(Palette.tertiaryInk)
                Text(price, format: .currency(code: "USD"))
                    .foregroundStyle(Palette.ink)
            }
            .font(DesignTokens.caption)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
        }
        .frame(width: Self.width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.string(
                "Average cost %@, price %@", cost.formatted(.currency(code: "USD")), price.formatted(.currency(code: "USD"))))
    }
}
