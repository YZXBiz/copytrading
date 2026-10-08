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
        NavigationStack {
            Form {
                SheetTitle(
                    kind: L10n.string("Guru"),
                    name: route.displayName.trimmed.isEmpty ? L10n.string("New") : route.displayName.trimmed)
                Section {
                    TextField(L10n.string("Name"), text: $route.displayName, prompt: Text(L10n.string("How you refer to this guru")))
                        .accessibilityLabel(L10n.string("Name"))
                } header: {
                    SetupSectionHeader(title: "Guru", detail: "The trader whose calls CopyTrading copies.")
                }

                Section {
                    if channelIDs.isEmpty {
                        Text(L10n.string("Add the channel they post in under Discord in Connections first."))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(L10n.string("Discord channel"), selection: $route.channelID) {
                            Text(L10n.string("First channel in Connections (%@)", channelIDs[0])).tag("")
                            ForEach(channelChoices, id: \.self) { channelID in
                                Text(channelID).tag(channelID)
                            }
                        }
                    }
                    TextField(
                        L10n.string("Author ID"), text: $route.authorID, prompt: Text(L10n.string("Needed when several people post there"))
                    )
                    .accessibilityLabel(L10n.string("Author ID"))
                } header: {
                    SetupSectionHeader(
                        title: "Where they post", detail: "The channel and, in a shared channel, the guru's Discord user ID.",
                        help: [SetupHelp.channelID, SetupHelp.userID])
                }

                PlaybookSection(route: $route, learn: learn)

                ForEach($route.examples) { $example in
                    ExampleEditorSection(
                        example: $example,
                        index: route.examples.firstIndex { $0.id == example.id } ?? 0,
                        remove: { removeExample(example.id) }
                    )
                }
                Section {
                    Button(L10n.string("Add Example"), systemImage: "plus", action: addExample)
                        .buttonStyle(.borderless)
                } footer: {
                    Text(
                        L10n.string(
                            "Start Copying first reads each example with the interpreter. A different reading stops copying from starting.")
                    )
                }

                GuruRulesSection(route: $route)

                GuruReplaySection(route: route, policies: policies, replay: replay)

                DestinationEditorSection(
                    connection: $route.connection,
                    accountIDs: accountIDs,
                    policy: route.connection.flatMap { policies[$0.accountID.trimmed] }
                )

                Section {
                    Button(L10n.string("Remove Guru"), role: .destructive, action: removeGuru)
                        .buttonStyle(.borderless)
                } footer: {
                    Text(L10n.string("Removing takes effect when the setup is checked and copying starts."))
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done"), action: dismiss.callAsFunction)
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 680, idealHeight: 760)
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
