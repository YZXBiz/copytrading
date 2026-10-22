import AppLocalizationCore
import SwiftUI

/// A service's logo on a small white tile, as Connections lists services; an SF Symbol on a tile
/// that follows the appearance stands in where the app has no logo.
struct ServiceIcon: View {
    var brand: String?
    var symbol = "server.rack"
    var size: CGFloat = 30

    var body: some View {
        if let brand, let image = BrandIcon.image(named: brand) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.62, height: size * 0.62)
                .modifier(Tile(size: size, fill: .white, border: .black.opacity(0.08)))
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.45))
                .foregroundStyle(Palette.secondaryInk)
                .modifier(Tile(size: size, fill: Palette.tile, border: Palette.hairline))
        }
    }

    private struct Tile: ViewModifier {
        let size: CGFloat
        let fill: Color
        let border: Color

        func body(content: Content) -> some View {
            content
                .frame(width: size, height: size)
                .background(fill, in: .rect(cornerRadius: size * 0.27, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .strokeBorder(border)
                }
                .accessibilityHidden(true)
        }
    }
}
