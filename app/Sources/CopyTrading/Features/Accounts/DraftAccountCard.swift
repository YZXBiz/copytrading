import DesktopCore
import SwiftUI

/// A broker account added or changed in the setup but not saved yet, written as a few plain
/// sentences: what kind of account it is, the limits its orders stay inside, and whether its keys
/// are in. The whole card opens the editor.
struct DraftAccountCard: View {
    let account: TradingAccountDraft
    let hasSavedKeys: Bool
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    @MainActor private var name: String {
        account.name.trimmed.isEmpty ? L10n.string("Unnamed account") : account.name.trimmed
    }

    private var isLive: Bool { account.environment == .live }

    private var tint: Color {
        switch (isLive, colorScheme == .dark) {
        case (false, false): Color(red: 0.937, green: 0.973, blue: 0.965)
        case (true, false): Color(red: 1.0, green: 0.961, blue: 0.929)
        case (false, true): Color(red: 0.13, green: 0.17, blue: 0.18)
        case (true, true): Color(red: 0.2, green: 0.16, blue: 0.13)
        }
    }

    @MainActor private var kind: String {
        L10n.string(
            isLive
                ? "A live Alpaca account. Its orders use real money."
                : "A paper Alpaca account: pretend money at real prices."
        )
    }

    @MainActor private var limits: String {
        let policy = account.policy
        return L10n.string(
            "Up to %@ an order and %@ in all. It stops for the day after a %@ loss.",
            money(policy.maxOrderUSD), money(policy.maxTotalUSD), money(policy.dailyLossCapUSD)
        )
    }

    private var keysTyped: Bool { !account.key.isEmpty && !account.secret.isEmpty }

    private var keysIn: Bool { keysTyped || hasSavedKeys }

    @MainActor private var keys: String {
        if keysTyped { return L10n.string("Its Alpaca keys are in.") }
        if hasSavedKeys { return L10n.string("Its Alpaca keys are saved in your Keychain.") }
        return L10n.string("Its Alpaca keys aren’t in yet.")
    }

    var body: some View {
        FramedCard(tint: tint, isHovered: isHovered) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(name)
                        .font(DesignTokens.cardSerif.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    DraftMark()
                }
                Text(kind)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(isLive ? .orange : Palette.secondaryInk)
                Text(limits)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Image(systemName: keysIn ? "key.fill" : "key")
                        .imageScale(.small)
                        .foregroundStyle(Palette.tertiaryInk)
                        .accessibilityHidden(true)
                    Text(keys)
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.ink)
                    if !keysIn {
                        InlineActionMark(title: "Add Keys…")
                    }
                }
                .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Whole dollars without cents, as a person would say a limit.
    private func money(_ value: String) -> String {
        guard let decimal = Decimal(string: value) else { return Humanize.usd(value) }
        return decimal.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
