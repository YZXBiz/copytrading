import SwiftUI

/// A guru added or changed in the setup but not saved yet, in plain sentences: who they are, where
/// they post, whether their playbook is ready, and which accounts copy them. The whole card opens
/// the editor.
struct DraftGuruCard: View {
    let route: TradingRouteDraft
    let channel: String
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isUnnamed: Bool { route.displayName.trimmed.isEmpty }

    @MainActor private var name: String {
        isUnnamed ? L10n.string("Unnamed guru") : route.displayName.trimmed
    }

    private var tint: Color {
        colorScheme == .dark ? Color(red: 0.17, green: 0.16, blue: 0.21) : Color(red: 0.961, green: 0.953, blue: 0.996)
    }

    private var lines: Int {
        route.playbook.split(whereSeparator: \.isNewline).count
    }

    private var destinations: [String] {
        route.connections.map { $0.accountID.trimmed }.filter { !$0.isEmpty }
    }

    @MainActor private var copies: String {
        switch destinations.count {
        case 0: L10n.string("It doesn’t copy into an account yet.")
        case 1: L10n.string("Copies into %@.", destinations[0])
        default:
            L10n.string(
                "Copies into %@ and %@.", destinations.dropLast().joined(separator: ", "), destinations.last ?? ""
            )
        }
    }

    var body: some View {
        FramedCard(tint: tint, isHovered: isHovered) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    GuruMonogram(name: name, size: 34)
                    Spacer(minLength: 8)
                    DraftMark()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(DesignTokens.cardSerif.weight(.semibold))
                        .foregroundStyle(isUnnamed ? Palette.secondaryInk : Palette.ink)
                        .lineLimit(1)
                    Text(
                        channel.isEmpty
                            ? L10n.string("No channel yet")
                            : L10n.string("Posts in channel %@", channel)
                    )
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Text(
                    lines == 0
                        ? L10n.string("No playbook yet. Open it to learn one from the channel.")
                        : L10n.string("Its playbook is ready, %@.", Humanize.count(lines, "line"))
                )
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(copies)
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if destinations.isEmpty {
                        InlineActionMark(title: "Choose Accounts…")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
