import SwiftUI

/// One kind of post in "What CopyTrading does": the kind, an example as the guru wrote it, and
/// what CopyTrading does with it.
struct GuideCapabilityRow: View {
    let kind: String
    let example: String
    let does: String

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(kind))
                    .font(DesignTokens.caption.weight(.medium))
                    .foregroundStyle(Palette.tertiaryInk)
                // The guru's own words, so they are never translated.
                Text(verbatim: example)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.well, in: .rect(cornerRadius: 8))
            }
            .frame(width: 210, alignment: .leading)
            Text(localizedMarkdown(does))
                .font(DesignTokens.documentBody)
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
