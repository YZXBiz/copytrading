import DesktopCore
import SwiftUI

/// One guru: where they post, how to read their calls, how they trade, and the account that
/// copies them.
struct RouteEditorSheet: View {
    @Binding var route: TradingRouteDraft
    /// The accounts this guru may copy into: those no other guru copies into.
    let accountIDs: [String]
    /// Each account's limits, by account name, for sizing.
    let policies: [String: TradingAccountPolicy]
    let channelIDs: [String]
    let learn: (TradingRouteDraft) async throws -> LearnedGuruPlaybook
    /// Reads recent posts with this draft before the guru is switched on.
    let replay: (TradingRouteDraft) async throws -> GuruReplay
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(
            kind: L10n.string("Guru"),
            title: route.displayName.trimmed.isEmpty ? L10n.string("New") : route.displayName.trimmed,
            lede: L10n.string("The trader whose calls CopyTrading copies.")
        ) {
            // The name sits right under the title it fills in; the header already says "Guru".
            SheetField(title: L10n.string("Name")) {
                TextField(L10n.string("Name"), text: $route.displayName, prompt: Text(L10n.string("How you refer to this guru")))
                    .accessibilityLabel(L10n.string("Name"))
            }

            SheetSection(
                L10n.string("Where they post"),
                detail: L10n.string("The channel and, in a shared channel, the guru's Discord user ID.")
            ) {
                if channelIDs.isEmpty {
                    Text(L10n.string("Add the channel they post in under Discord in Connections first."))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.vertical, 12)
                } else {
                    SheetRow(title: L10n.string("Discord channel")) {
                        SheetMenu(
                            label: L10n.string("Discord channel"),
                            choices: [("", L10n.string("First channel in Connections (%@)", channelIDs[0]))]
                                + channelChoices.map { ($0, $0) },
                            selection: $route.channelID)
                    }
                }
                SheetField(title: L10n.string("Author ID")) {
                    TextField(
                        L10n.string("Author ID"), text: $route.authorID,
                        prompt: Text(L10n.string("Needed when several people post there"))
                    )
                    .accessibilityLabel(L10n.string("Author ID"))
                }
            } accessory: {
                HelpPopoverButton(articles: [SetupHelp.channelID, SetupHelp.userID])
            }

            PlaybookSection(route: $route, learn: learn)

            ForEach($route.examples) { $example in
                ExampleEditorSection(
                    example: $example,
                    index: route.examples.firstIndex { $0.id == example.id } ?? 0,
                    remove: { removeExample(example.id) }
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                Button(L10n.string("Add Example"), systemImage: "plus", action: addExample)
                    .buttonStyle(SheetQuietButtonStyle())
                Text(
                    L10n.string(
                        "Start Copying first reads each example with the interpreter. A different reading stops copying from starting.")
                )
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }

            GuruRulesSection(route: $route)

            GuruReplaySection(route: route, policies: policies, replay: replay)

            DestinationEditorSection(
                connection: $route.connection,
                accountIDs: accountIDs,
                policy: route.connection.flatMap { policies[$0.accountID.trimmed] }
            )
        } leading: {
            Button(L10n.string("Remove Guru"), role: .destructive, action: removeGuru)
                .buttonStyle(SheetQuietButtonStyle(isDestructive: true))
                .help(L10n.string("Removing takes effect when the setup is checked and copying starts."))
        } actions: {
            Button(L10n.string("Done"), action: dismiss.callAsFunction)
                .buttonStyle(SheetButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 680, idealHeight: 780)
    }

    private var channelChoices: [String] {
        route.channelID.isEmpty || channelIDs.contains(route.channelID)
            ? channelIDs
            : channelIDs + [route.channelID]
    }

    private func addExample() {
        route.examples.append(TradingProfileExampleDraft())
    }

    private func removeExample(_ id: UUID) {
        route.examples.removeAll { $0.id == id }
    }

    private func removeGuru() {
        dismiss()
        remove()
    }
}
