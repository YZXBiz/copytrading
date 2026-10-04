import DesktopCore
import SwiftUI

/// One guru: where they post, how to read their calls, and which accounts copy them.
struct RouteEditorSheet: View {
    @Binding var route: TradingRouteDraft
    let accountIDs: [String]
    let channelIDs: [String]
    let learn: (TradingRouteDraft) async throws -> LearnedGuruPlaybook
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

                Section {
                    TextField(L10n.string("Message prefix"), text: $route.prefix, prompt: Text(L10n.string("e.g. %@", "ALERT:")))
                        .accessibilityLabel(L10n.string("Message prefix"))
                    Picker(L10n.string("Exit fractions apply to"), selection: $route.exitBasis) {
                        Text(L10n.string("Original position")).tag(TradingExitBasis.originalPosition)
                        Text(L10n.string("Remaining position")).tag(TradingExitBasis.remainingPosition)
                    }
                } header: {
                    SetupSectionHeader(title: "Reading their posts", detail: "Learn from Channel fills these in; edit anything.")
                } footer: {
                    Text(L10n.string("Only messages starting with the prefix are read as calls."))
                }

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
                            "Check Setup reads each example with the interpreter. A different reading stops the setup from starting."))
                }

                ForEach($route.connections) { $connection in
                    DestinationEditorSection(
                        connection: $connection,
                        accountIDs: accountIDs,
                        canRemove: route.connections.count > 1,
                        remove: { removeConnection(connection.id) }
                    )
                }
                Section {
                    if accountIDs.isEmpty {
                        Text(L10n.string("Add a broker account in Accounts, then choose it here."))
                            .foregroundStyle(.secondary)
                    } else {
                        Button(
                            L10n.string(route.connections.isEmpty ? "Choose an Account to Copy Into" : "Copy into Another Account"),
                            systemImage: "plus", action: addConnection
                        )
                        .buttonStyle(.borderless)
                    }
                }

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

    private func addConnection() {
        let used = Set(route.connections.map(\.accountID))
        let next = accountIDs.first { !used.contains($0) } ?? accountIDs.first ?? ""
        route.connections.append(TradingConnectionDraft(accountID: next))
    }

    private func removeConnection(_ id: UUID) {
        route.connections.removeAll { $0.id == id }
    }

    private func removeGuru() {
        dismiss()
        remove()
    }
}
