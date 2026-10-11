import SwiftUI

/// A guru's initials inside a thin ink ring. `tint(for:)` keeps a steady colour per name for the
/// few places that still need to tell gurus apart.
struct GuruMonogram: View {
    let name: String
    var size: CGFloat = 28

    private static let tints: [Color] = [.indigo, .teal, .pink, .brown, .mint, .purple, .cyan, .orange]

    private var initials: String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var tint: Color { Self.tint(for: name) }

    /// The same muted tint for the same name everywhere it appears.
    static func tint(for name: String) -> Color {
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return tints[seed % tints.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.2))
            .accessibilityHidden(true)
    }
}
