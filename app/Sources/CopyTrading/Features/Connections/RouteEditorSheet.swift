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
    @State private var confirmsRemove = false

    var body: some View {
        SheetScaffold(
            kind: L10n.string("Guru"),
            title: route.displayName.trimmed.isEmpty ? L10n.string("New") : route.displayName.trimmed,
            lede: L10n.string("Whose calls to copy, where they post, and which account copies them."),
            monogram: route.displayName.trimmed.isEmpty ? nil : route.displayName.trimmed,
            facts: facts
        ) {
            // The name sits right under the title it fills in; the header already says "Guru".
            SheetField(title: L10n.string("Name")) {
                TextField(
                    L10n.string("Name"), text: $route.displayName,
                    prompt: Text(L10n.string("How you refer to this guru")).foregroundStyle(Palette.tertiaryInk)
                )
                .accessibilityLabel(L10n.string("Name"))
            }

            SheetSection(L10n.string("Where they post")) {
                if channelIDs.isEmpty {
                    Text(L10n.string("Add the channel they post in under Discord in Connections first."))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.vertical, 12)
                } else {
                    SheetRow(title: L10n.string("Discord channel"), labelsControl: true) {
                        // Each channel once: a guru with no channel of its own reads as the first.
                        SheetMenu(
                            label: L10n.string("Discord channel"),
                            choices: channelChoices.map { ($0, $0) },
                            selection: channelSelection)
                    }
                }
                SheetField(title: L10n.string("Guru's Discord user ID (optional)")) {
                    TextField(
                        L10n.string("Guru's Discord user ID"), text: $route.authorID,
                        prompt: Text(L10n.string("Leave blank if only the guru posts in this channel")).foregroundStyle(
                            Palette.tertiaryInk)
                    )
                    .accessibilityLabel(L10n.string("Guru's Discord user ID"))
                }
            } accessory: {
                HelpPopoverButton(articles: [SetupHelp.channelID, SetupHelp.userID])
            }
            .icon(brand: "discord")
            .mark(channelIDs.isEmpty ? .needsYou : .done)

            DestinationEditorSection(
                connection: $route.connection,
                accountIDs: accountIDs,
                policy: route.connection.flatMap { policies[$0.accountID.trimmed] },
                guruName: route.displayName
            )

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

        } leading: {
            Button(L10n.string("Remove Guru…"), role: .destructive) { confirmsRemove = true }
                .buttonStyle(SheetQuietButtonStyle(isDestructive: true))
                .confirmationDialog(
                    L10n.string("Remove %@?", route.displayName.trimmed.isEmpty ? L10n.string("this guru") : route.displayName.trimmed),
                    isPresented: $confirmsRemove
                ) {
                    Button(L10n.string("Remove Guru"), role: .destructive, action: removeGuru)
                    Button(L10n.string("Keep"), role: .cancel) {}
                } message: {
                    Text(
                        L10n.string(
                            "Their calls stop being copied once you start copying with this change. Shares they bought stay in the account."
                        ))
                }
        } actions: {
            Button(L10n.string("Done"), action: dismiss.callAsFunction)
                .buttonStyle(SheetButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 680, idealHeight: 780)
    }

    /// The guru at a glance: where they post, where their calls go, and what a full position is.
    private var facts: [SheetFact] {
        var facts: [SheetFact] = []
        let channel = channelSelection.wrappedValue
        facts.append(
            channel.isEmpty
                ? SheetFact(symbol: "exclamationmark", text: L10n.string("No channel yet"), tint: Palette.butter)
                : SheetFact(brand: "discord", text: Self.shortID(channel)))
        if let accountID = route.connection?.accountID.trimmed, !accountID.isEmpty {
            facts.append(SheetFact(brand: "alpaca", text: accountID, tint: Palette.sky))
            if let full = policies[accountID]?.maxSymbolUSD.trimmed, let amount = Decimal(string: full), amount > 0 {
                facts.append(
                    SheetFact(
                        symbol: "dollarsign",
                        text: L10n.string("Full position %@", amount.formatted(.currency(code: "USD").precision(.fractionLength(0...2))))))
            }
        } else {
            facts.append(SheetFact(symbol: "exclamationmark", text: L10n.string("No account yet"), tint: Palette.butter))
        }
        return facts
    }

    /// A Discord ID shortened to its ends: "1517…9742".
    private static func shortID(_ id: String) -> String {
        id.count > 10 ? "\(id.prefix(4))…\(id.suffix(4))" : id
    }

    private var channelSelection: Binding<String> {
        Binding(
            get: { route.channelID.isEmpty ? channelIDs.first ?? "" : route.channelID },
            set: { route.channelID = $0 })
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

#if DEBUG
    #Preview("Guru: Zhao") {
        @Previewable @State var route = TradingRouteDraft(
            channelID: "1517754775674949742",
            displayName: "Zhao-official",
            playbook: """
                5.90加了6分之一常规仓soun -> buy SOUN at 5.90, fraction 1/6
                12.13加了6分之一常规仓f -> buy F at 12.13, fraction 1/6
                93.2出一半92.3的soxl -> sell half of the SOXL bought at 92.3, at 93.2
                """,
            connection: TradingConnectionDraft(accountID: "zhap-account-2")
        )
        var policy = TradingAccountPolicy()
        policy.maxOrderUSD = "250"
        policy.maxSymbolUSD = "1000"
        return RouteEditorSheet(
            route: $route,
            accountIDs: ["zhap-account-2"],
            policies: ["zhap-account-2": policy],
            channelIDs: ["1517754775674949742"],
            learn: { _ in throw CancellationError() },
            replay: { _ in throw CancellationError() },
            remove: {}
        )
        .frame(width: 660, height: 900)
    }
#endif
