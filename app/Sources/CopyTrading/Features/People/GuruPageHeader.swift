import SwiftUI

/// The top of a guru's page: their name large, where their calls go in a quiet line under it, and
/// Edit as a soft pill.
struct GuruPageHeader: View {
    let name: String
    let destinations: AttributedString?
    /// An edit waiting on Apply Changes; the line above still shows the saved setup.
    let pendingNote: String?
    let edit: () -> Void
    let review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identity
            if let pendingNote {
                // An edit is only in the setup until it is applied; say so where it shows.
                HStack(spacing: 12) {
                    Label(pendingNote, systemImage: "pencil.circle")
                        .foregroundStyle(Palette.secondaryInk)
                    Button(L10n.string("Review in Connections"), action: review)
                        .buttonStyle(QuietTextButtonStyle())
                }
                .font(DesignTokens.caption)
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                // A person's name wraps rather than losing its middle to an ellipsis.
                Text(name)
                    .font(DesignTokens.entityTitle)
                    .tracking(DesignTokens.entityTitleTracking)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let destinations {
                    Text(destinations)
                        .font(DesignTokens.lede)
                        .tracking(DesignTokens.ledeTracking)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 16)
            Button(L10n.string("Edit"), action: edit)
                .buttonStyle(PageButtonStyle())
                .help(L10n.string("Edit %@", name))
                .accessibilityLabel(L10n.string("Edit %@", name))
                .accessibilityIdentifier("guru.edit")
        }
    }
}
