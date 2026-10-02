import DesktopCore
import SwiftUI

/// One captured embed, shown only when it contains readable source content.
struct ActivityCapturedEmbedView: View {
    let embed: SourceEmbedEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title = embed.title, ActivitySourceText.hasReadableText(title) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let description = embed.description, ActivitySourceText.hasReadableText(description) {
                Text(description)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(embed.fields.enumerated()), id: \.offset) { _, field in
                if ActivitySourceText.hasReadableText(field.name)
                    || ActivitySourceText.hasReadableText(field.value)
                {
                    VStack(alignment: .leading, spacing: 2) {
                        if ActivitySourceText.hasReadableText(field.name) {
                            Text(field.name)
                                .font(DesignTokens.caption)
                                .foregroundStyle(Palette.tertiaryInk)
                        }
                        if ActivitySourceText.hasReadableText(field.value) {
                            Text(field.value)
                                .font(DesignTokens.bodyText)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
