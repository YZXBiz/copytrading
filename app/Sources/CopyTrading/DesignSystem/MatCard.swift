import SwiftUI

/// A thumbnail in a soft mat, for a grid of cards: a 7pt mat that fades from
/// its tone at the top to grey at the bottom, 18pt outer corners, 12pt page corners. Used for the
/// People grid only; screens use a `Page`.
struct MatCard<Content: View>: View {
    let tone: MatTone
    var padding: CGFloat = 22
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.page, in: .rect(cornerRadius: 12))
        .padding(7)
        .background(
            LinearGradient(colors: [tone.top, tone.bottom], startPoint: .top, endPoint: .bottom)
                .opacity(colorScheme == .dark ? 0.35 : 1),
            in: .rect(cornerRadius: 18)
        )
        .shadow(color: .black.opacity(0.08), radius: 1)
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    @Environment(\.colorScheme) private var colorScheme
}
