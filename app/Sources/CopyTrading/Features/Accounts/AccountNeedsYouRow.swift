import DesktopCore
import SwiftUI

/// One waiting call: what copying it would place, who posted it and when, and the two answers.
struct AccountNeedsYouRow: View {
    let call: WaitingCall
    let guruName: String?
    let canCopy: Bool
    let copy: () -> Void
    let skip: () -> Void

    @MainActor private var title: String {
        guard let first = call.calls.first else { return L10n.string("Enter the trade yourself") }
        let rest = call.calls.count > 1 ? L10n.string(" and %lld more", Int64(call.calls.count - 1)) : ""
        return first.phrase + rest
    }

    @MainActor private var detail: String {
        var parts: [String] = []
        if let guruName { parts.append(guruName) }
        let post = call.source.readableText()
        if !post.isEmpty { parts.append("“\(post)”") }
        parts.append(Humanize.feedTime(call.source.sourceAt))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ToneGlyph(symbol: "hourglass", tint: Palette.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.feedTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Button(L10n.string("Skip"), action: skip)
                .buttonStyle(PageButtonStyle())
                .accessibilityIdentifier("needsYou.skip")
            Button(
                L10n.string(call.calls.isEmpty ? "Enter Trade…" : call.awaitsApproval ? "Approve…" : "Copy…"),
                action: copy
            )
            .buttonStyle(PageButtonStyle(isProminent: true))
            .disabled(!canCopy)
            .accessibilityIdentifier("needsYou.copy")
            .accessibilityHint(L10n.string("Opens the call to check, then previews the order in each waiting account."))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
