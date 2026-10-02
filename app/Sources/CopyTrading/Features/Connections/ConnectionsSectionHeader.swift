import SwiftUI

/// A Connections section's title and what it is for, such as "Your Discord Connection", with
/// its add button at the trailing edge. An empty section shows only its title; its offer card
/// says what it is for.
struct ConnectionsSectionHeader: View {
    let title: String
    var subtitle: String?
    var addTitle: String?
    var add: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(title))
                    .font(.system(.title3, weight: .semibold).scaled(by: 17.0 / 15))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(L10n.string(subtitle))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: 12)
            if let add, let addTitle {
                Button(L10n.string(addTitle), systemImage: "plus.square", action: add)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Palette.tertiaryInk)
                    .help(L10n.string(addTitle))
            }
        }
    }
}
