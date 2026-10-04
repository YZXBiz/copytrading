import AppLocalizationCore
import SwiftUI

/// A service's logo on a small white tile, as Connections lists services; an SF Symbol stands in
/// where the app has no logo.
struct ServiceIcon: View {
    var brand: String?
    var symbol = "server.rack"
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let brand, let image = BrandIcon.image(named: brand) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.62, height: size * 0.62)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Color.black.opacity(0.62))
            }
        }
        .frame(width: size, height: size)
        .background(.white, in: .rect(cornerRadius: size * 0.27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(.black.opacity(0.08))
        }
        .accessibilityHidden(true)
    }
}
