import SwiftUI

/// One service in Connections: its logo, what it needs or how it is set up, and one action at the
/// trailing edge, "Connect" or "Edit", or a chevron for a list behind it. A panel grows out of
/// the row that opened it.
struct ConnectionServiceRow: View {
    let brand: String?
    var symbol = "server.rack"
    /// A guru's name, drawn as their monogram in place of a logo.
    var monogram: String?
    let title: String
    var detail: String?
    var tone: StatusTone?
    /// The action's word; nil shows a chevron.
    var action: String?
    /// Which way the chevron points: a list behind the row, or one that opens and closes in place.
    var chevron: Chevron = .forward
    /// Where a panel opened from this row grows from; rows that open a sheet have none.
    var origin: ConnectionPanelOrigin?
    let identifier: String
    let perform: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                if let monogram {
                    GuruMonogram(name: monogram, size: 30)
                } else {
                    ServiceIcon(brand: brand, symbol: symbol)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.ink)
                    if let detail {
                        HStack(spacing: 5) {
                            if let tone {
                                Image(systemName: tone.symbol)
                                    .imageScale(.small)
                                    .foregroundStyle(tone.color)
                            }
                            Text(detail)
                                .font(.body)
                                .foregroundStyle(Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let action {
                    Text(action)
                        .foregroundStyle(Palette.accent)
                } else {
                    Image(systemName: chevron.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(.rect)
            .background(Palette.ink.opacity(isHovered ? 0.04 : 0))
        }
        .buttonStyle(QuietPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .anchorPreference(key: ConnectionOriginKey.self, value: .bounds) { anchor in origin.map { [$0: anchor] } ?? [:] }
        // The label replaces the row's words; the element stays the button, so it can be pressed.
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(action ?? "")
        .accessibilityIdentifier(identifier)
    }
}

extension ConnectionServiceRow {
    enum Chevron {
        case forward, collapsed, expanded

        var symbol: String {
            switch self {
            case .forward: "chevron.right"
            case .collapsed: "chevron.down"
            case .expanded: "chevron.up"
            }
        }
    }
}
