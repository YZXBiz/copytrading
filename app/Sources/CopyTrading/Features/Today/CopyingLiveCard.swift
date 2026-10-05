import DesktopCore
import SwiftUI

/// Right after a new setup starts copying: who is copied into which accounts, and that CopyTrading
/// is listening for the next post. It stays until that post arrives, copying stops, or the owner
/// closes it.
struct CopyingLiveCard: View {
    let model: AppModel
    let feature: AccountFeatureModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRippled = false
    @Environment(\.colorSchemeContrast) private var contrast

    @MainActor private var title: String {
        let configuration = model.savedTradingConfiguration
        let gurus = GuruDirectory(configuration).gurus.map(\.name)
        let accounts = (configuration?.accounts ?? []).map {
            L10n.string("%@ (%@)", $0.id, L10n.string($0.environment == .live ? "Live" : "Paper"))
        }
        let who = gurus.isEmpty ? L10n.string("your gurus") : localizedList(gurus)
        let into = accounts.isEmpty ? L10n.string("your accounts") : localizedList(accounts)
        return L10n.string("You're copying %@ into %@.", who, into)
    }

    @MainActor private func localizedList(_ values: [String]) -> String {
        guard let last = values.last else { return "" }
        guard values.count > 1 else { return last }
        let prefix = Humanize.joined(Array(values.dropLast()))
        return values.count == 2
            ? L10n.string("%@ and %@", prefix, last)
            : L10n.string("%@, and %@", prefix, last)
    }

    /// Accounts in the setup that have never been allowed to buy.
    private var hasAccountsWithEntriesOff: Bool {
        feature.accounts.contains { $0.activeConfiguration && $0.entryPermission == "disabled" }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.accent)
                // A few ripples when the card appears, then still: a symbol that animates forever
                // keeps the window redrawing, which costs a third of a core behind a sheet.
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeat(3), value: hasRippled)
                .task { hasRippled = !reduceMotion }
                .frame(width: 38, height: 38)
                .background(Palette.accent.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DesignTokens.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    L10n.string(
                        "CopyTrading is listening for the next post. It will show up here and in Activity, with what each account did.")
                )
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                if hasAccountsWithEntriesOff {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Label(
                            L10n.string(
                                "New accounts start with entries off, so nothing is bought yet. Turn them on in Accounts when you're ready."
                            ),
                            systemImage: "lightbulb"
                        )
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        Button(L10n.string("Open Accounts"), action: openAccounts)
                            .buttonStyle(.link)
                            .font(DesignTokens.bodyText)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            Button(L10n.string("Close"), systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.tertiaryInk)
                .help(L10n.string("Close"))
        }
        .padding(DesignTokens.workingSurfacePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.readingCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.readingCornerRadius)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.accent.opacity(0.3), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.copyingLive")
    }

    private func openAccounts() {
        model.selectedScreen = .accounts
    }

    private func close() {
        model.copyingStartedAt = nil
    }
}
