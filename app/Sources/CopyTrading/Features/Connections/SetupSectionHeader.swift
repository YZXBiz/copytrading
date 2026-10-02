import SwiftUI

/// A settings group's title: a small bold title and a grey line under it, with
/// "Where do I find this?" at the trailing edge when the section asks for keys or IDs.
struct SetupSectionHeader: View {
    let title: String
    let detail: String
    var status: ConnectionStatus?
    var help: [HelpArticle] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(L10n.string(detail))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiaryInk)
                    .textCase(nil)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string("%@, %@", title, detail))
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let status {
                StatusBadge(status.text, tone: status.tone)
                    .font(.caption)
                    .textCase(nil)
            }
            if !help.isEmpty {
                HelpPopoverButton(articles: help)
                    .textCase(nil)
            }
        }
        .padding(.bottom, 2)
    }
}
