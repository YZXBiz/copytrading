import DesktopCore
import SwiftUI

/// What already came of the post, folded under HISTORY: each account's earlier outcome, then the
/// trades sent by hand for it before.
struct ManualReviewHistory: View {
    let source: SourceActivity
    let feature: ManualReviewFeatureModel
    let operations: (any ManualReviewOperations)?
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var commands: [ManualCommandResult] {
        feature.commandResults.values
            .filter { $0.command.sourceID == source.sourceID }
            .sorted { $0.command.confirmedAt > $1.command.confirmedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Eyebrow(L10n.string("History"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(QuietPressButtonStyle())
            .accessibilityIdentifier("review.history")
            .accessibilityValue(Text(L10n.string(isOpen ? "Shown" : "Hidden")))
            if isOpen {
                VStack(alignment: .leading, spacing: 24) {
                    if source.destinations.isEmpty, commands.isEmpty {
                        Text(L10n.string("Nothing has come of this post yet."))
                            .font(DesignTokens.bodyText)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                    ForEach(source.destinations) { destination in
                        DestinationResultView(destination: destination)
                    }
                    ForEach(commands, id: \.command.request.commandID) { result in
                        command(result)
                    }
                    ForEach(feature.commandPages.keys.sorted(), id: \.self) { accountID in
                        if feature.commandPages[accountID]?.nextBeforeCommandID != nil {
                            Button(L10n.string("Load earlier commands for %@", accountID)) {
                                Task {
                                    await feature.loadEarlierCommands(accountID: accountID, sourceID: source.sourceID, using: operations)
                                }
                            }
                            .buttonStyle(InkActionButtonStyle(isProminent: false))
                            .disabled(feature.pendingCommandPages.contains(accountID))
                        }
                        if let error = feature.errors["history:\(accountID)"] {
                            Callout(error, tone: .critical)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOpen)
    }

    @MainActor private func command(_ result: ManualCommandResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("%@ · trade %lld", result.command.request.accountID, Int64(result.command.instructionIndex + 1)))
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                StatusBadge(Humanize.code(result.status), tone: StatusTone(code: result.status))
            }
            if let reason = result.reason {
                Text(Reason.text(reason))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            HStack(spacing: 12) {
                if let orderStatus = result.orderStatus {
                    Text(L10n.string("Order %@ · filled %@", L10n.string(Humanize.code(orderStatus).lowercased()), result.filledQuantity))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                }
                Button(L10n.string("Refresh Status")) {
                    Task {
                        await feature.commandResult(
                            accountID: result.command.request.accountID, commandID: result.command.request.commandID, using: operations)
                    }
                }
                .buttonStyle(QuietPressButtonStyle())
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .disabled(operations == nil || feature.pendingCommands.contains(result.command.request.commandID))
            }
        }
        .help(L10n.string("Command %@", result.command.request.commandID))
    }
}
