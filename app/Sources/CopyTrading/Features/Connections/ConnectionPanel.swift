import SwiftUI

/// The sheet Connections opens over its page: the service's logo and a plain title, a hairline,
/// and its content on a quiet surface.
struct ConnectionPanel<Content: View>: View {
    let title: String
    let brand: String?
    var symbol = "server.rack"
    let close: () -> Void
    /// Esc closes the sheet, except while something above it, such as the assistant, takes Esc.
    var escapeCloses = true
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ServiceIcon(brand: brand, symbol: symbol, size: 28)
                Text(title)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(L10n.string("Close"), systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 24, height: 24)
                    .background(Palette.ink.opacity(0.07), in: .circle)
                    .keyboardShortcut(escapeCloses ? .cancelAction : nil)
                    .help(L10n.string("Close"))
                    .accessibilityIdentifier("connections.close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1 / displayScale)
                .padding(.horizontal, 20)

            content
                .padding(20)
        }
        .frame(width: 420)
        .background(Palette.page, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    contrast == .increased ? Palette.secondaryInk : Palette.hairline.opacity(colorScheme == .dark ? 1 : 0.7),
                    lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.14), radius: 30, y: 12)
    }
}
