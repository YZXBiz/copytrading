import SwiftUI

/// A screen's name, what it answers, and the way there, beside its picture in the guide.
struct GuideScreenDescription: View {
    let screen: AppModel.Screen
    let text: String
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string(screen.title), systemImage: screen.symbol)
                .font(DesignTokens.documentSubheading)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(localizedMarkdown(text))
                .font(DesignTokens.documentBody)
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.string("Show me"), systemImage: "arrow.right", action: open)
                .buttonStyle(.link)
                .font(DesignTokens.bodyText)
                .accessibilityLabel(L10n.string("Open %@", L10n.string(screen.title)))
        }
    }
}
