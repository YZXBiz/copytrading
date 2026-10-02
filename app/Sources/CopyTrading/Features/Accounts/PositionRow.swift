import DesktopCore
import SwiftUI

/// One symbol's shares. When CopyTrading bought some, a chevron opens the lots that make them up
/// and the line under the symbol says how many posts they came from.
struct PositionRow: View {
    /// How far lots and the symbol column sit in from the chevron's edge.
    static let lotInset: CGFloat = 22

    let position: AccountPositionView
    let isExpanded: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var posts: Int {
        Set(position.lots.map { $0.sourceID ?? $0.lotID }).count
    }

    var body: some View {
        if position.lots.isEmpty {
            // Shares held only outside CopyTrading have no lots to open; the row is plain.
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityIdentifier("accounts.position.\(position.symbol)")
        } else {
            Button(action: toggle) { content }
                .buttonStyle(QuietPressButtonStyle())
                .accessibilityLabel(accessibilityText)
                .accessibilityValue(L10n.string(isExpanded ? "Expanded" : "Collapsed"))
                .accessibilityHint(L10n.string("Shows the posts these shares came from"))
                .accessibilityIdentifier("accounts.position.\(position.symbol)")
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isExpanded)
                    .frame(width: Self.lotInset, alignment: .leading)
                    .opacity(position.lots.isEmpty ? 0 : 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(position.symbol)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                    if posts > 0 {
                        Text(L10n.string("from %@", Humanize.count(posts, "post")))
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cell(quantity(position.ownedQty))
            cell(quantity(position.externalQty))
            cell(position.brokerQty.map(quantity) ?? "—")
        }
        .padding(.vertical, 9)
        .contentShape(.rect)
    }

    @MainActor private var accessibilityText: String {
        var parts = [L10n.string("%@, %@ copied", position.symbol, quantity(position.ownedQty))]
        if posts > 0 { parts.append(L10n.string("from %@", Humanize.count(posts, "post"))) }
        parts.append(L10n.string("%@ held outside CopyTrading", quantity(position.externalQty)))
        if let broker = position.brokerQty { parts.append(L10n.string("%@ at broker", quantity(broker))) }
        return Humanize.joined(parts)
    }

    private func cell(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func quantity(_ value: String) -> String {
        Decimal(engine: value)?.formatted() ?? value
    }
}
