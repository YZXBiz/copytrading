import DesktopCore
import SwiftUI

/// Live accounts trade real money, so they are always marked distinctly from paper accounts.
struct EnvironmentBadge: View {
    let environment: TradingEnvironment

    var body: some View {
        switch environment {
        case .live:
            Label(L10n.string("Live"), systemImage: "dollarsign.circle.fill")
                .badgeStyle(.orange)
        case .paper:
            Label(L10n.string("Paper"), systemImage: "doc.text")
                .badgeStyle(.secondary)
        }
    }
}

extension View {
    fileprivate func badgeStyle(_ color: Color) -> some View {
        self
            .labelStyle(.titleAndIcon)
            .font(.caption.bold())
            .imageScale(.small)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(color.opacity(0.6)))
            .fixedSize()
    }
}
