import SwiftUI

/// A soft wash over the page with a window cut around the tour's target, edged by a thin accent
/// line and a faint glow. It never takes a click: the page underneath works as usual.
struct SetupTourSpotlight: View {
    let hole: CGRect
    var radius: CGFloat = 14
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.07, green: 0.08, blue: 0.11).opacity(colorScheme == .dark ? 0.42 : 0.24))
                .mask {
                    Rectangle()
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .frame(width: hole.width, height: hole.height)
                                .position(x: hole.midX, y: hole.midY)
                                .blur(radius: 1.5)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Palette.accent.opacity(0.9), lineWidth: 1.5)
                .frame(width: hole.width, height: hole.height)
                .position(x: hole.midX, y: hole.midY)
                .shadow(color: Palette.accent.opacity(0.45), radius: 10)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
