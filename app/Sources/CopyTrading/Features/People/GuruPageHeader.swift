import SwiftUI

/// The top of a guru's page: their initials, their name, where their calls go, and Edit.
struct GuruPageHeader: View {
    let name: String
    let destinations: String?
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            GuruMonogram(name: name, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(DesignTokens.pageTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let destinations {
                    Text(destinations)
                        .font(.body)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 16)
            Button(L10n.string("Edit"), action: edit)
                .buttonStyle(HairlineButtonStyle())
                .help(L10n.string("Edit %@", name))
                .accessibilityLabel(L10n.string("Edit %@", name))
                .accessibilityIdentifier("guru.edit")
        }
    }
}
