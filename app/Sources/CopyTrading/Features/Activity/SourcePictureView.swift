import AppKit
import SwiftUI

/// A picture the guru posted, shown whole at its own shape inside a hairline.
struct SourcePictureView: View {
    let image: NSImage
    var maxWidth: CGFloat = 520
    var maxHeight: CGFloat = 420

    var body: some View {
        let size = fitted
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .overlay(Rectangle().strokeBorder(Palette.hairline, lineWidth: 1))
            .accessibilityLabel(L10n.string("Picture from the post"))
    }

    /// The picture's own shape, scaled down (never up) to fit the space, so the hairline hugs it.
    private var fitted: CGSize {
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return CGSize(width: maxWidth, height: maxHeight) }
        let scale = min(1, maxWidth / natural.width, maxHeight / natural.height)
        return CGSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
    }
}
