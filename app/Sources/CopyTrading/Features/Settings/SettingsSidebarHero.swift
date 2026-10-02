import AppKit
import SwiftUI

/// The top of the Settings sidebar: the app's icon, tilted a little,
/// with what kind of money it trades, and its name.
struct SettingsSidebarHero: View {
    let model: AppModel

    private var badge: String? {
        guard let configuration = model.savedTradingConfiguration else { return nil }
        return configuration.accounts.contains { $0.environment == .live } ? "Live" : "Paper"
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(-5))
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 6)
                if let badge {
                    Text(L10n.string(badge))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(white: 0.1), in: .capsule)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                        .offset(x: 6, y: -2)
                }
            }
            Text("CopyTrading")
                .font(.system(.title2, weight: .semibold).scaled(by: 20.0 / 17))
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.map { L10n.string("CopyTrading, %@", L10n.string($0)) } ?? "CopyTrading")
    }
}
