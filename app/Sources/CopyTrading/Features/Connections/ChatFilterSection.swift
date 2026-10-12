import DesktopCore
import SwiftUI

/// The interpreter panel's optional chat filter (ADR-0012), under a hairline: with an OpenAI key,
/// a decision model sorts each post first, and small talk it is sure of is skipped before the
/// interpreter reads it. The panel's own Save checks the key; once it checks out the filter reads
/// as connected, with Remove to turn it off.
struct ChatFilterSection: View {
    @Bindable var model: AppModel
    /// The filter's latest check, while it failed and its key hasn't been edited since.
    let failedCheck: TradingCapabilityCheck?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var triage: TradingTriageConfiguration? { model.setupDraft.triage }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .padding(.bottom, 10)
            HStack(spacing: 8) {
                Eyebrow(L10n.string("Sort out chat first"))
                if triage == nil {
                    Eyebrow(L10n.string("Optional")).opacity(0.6)
                }
            }
            if let triage {
                connected(triage)
            } else {
                Text(
                    L10n.string(
                        "An OpenAI key skips small talk for about 15¢ per 1,000 posts, so %@ only reads calls.",
                        model.setupDraft.provider.shortTitle)
                )
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
                ConnectionField(label: "OpenAI key", focus: { isFocused = true }) {
                    SecureField(L10n.string("OpenAI key"), text: $model.setupDraft.triageAPIKey, prompt: Text(L10n.string("Optional")))
                        .focused($isFocused)
                        .accessibilityLabel(L10n.string("OpenAI key"))
                        .accessibilityIdentifier("connections.triageKey")
                }
                .padding(.top, 4)
                if let failedCheck {
                    ConnectionCheckCallout(check: failedCheck)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: triage)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: failedCheck)
    }

    private func connected(_ triage: TradingTriageConfiguration) -> some View {
        HStack(spacing: 8) {
            ServiceIcon(brand: triage.provider.brand, symbol: "line.3.horizontal.decrease", size: 20)
            Text(L10n.string("%@ · %@", triage.provider.title, triage.model))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.ink)
                .accessibilityLabel(L10n.string("Connected"))
            Spacer(minLength: 12)
            Button(L10n.string("Remove"), action: remove)
                .buttonStyle(.borderless)
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .accessibilityIdentifier("connections.triageRemove")
        }
        .accessibilityElement(children: .contain)
    }

    /// Turns the filter off: every post goes to the interpreter again once the setup is applied.
    private func remove() {
        model.setupDraft.triage = nil
        model.setupDraft.triageAPIKey = ""
    }
}
