import DesktopCore
import SwiftUI

/// One waiting call as a ticket on pale amber paper: how long it has waited and until when it can
/// be copied, what copying places, what that is worth against the buy it sells, the guru's own
/// message beside it, and the two answers. In the side rail it stacks into one column.
struct AccountCallTicket: View {
    let call: WaitingCall
    let guruName: String?
    let canCopy: Bool
    /// Copy… is the page's one ink capsule; otherwise it is outlined.
    let isPrimary: Bool
    /// The ticket sits in the narrow side rail, so its parts stack.
    let isCompact: Bool
    /// The first ticket takes ⌘↩ for Copy….
    let isFirst: Bool
    /// The post is open beside the page.
    let isSelected: Bool
    /// The chart's marker for this call is under the pointer, so the ticket answers it.
    let isHighlighted: Bool
    let now: Date
    let hover: (Bool) -> Void
    let open: () -> Void
    let copy: () -> Void
    let skip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor private var title: String {
        guard let first = call.calls.first else { return L10n.string("Enter the trade yourself") }
        let rest = call.calls.count > 1 ? L10n.string(" and %lld more", Int64(call.calls.count - 1)) : ""
        return first.phrase + rest
    }

    /// "+25.0% on the buy at $64,603.77": a sell that names the buy it sells, at its price.
    @MainActor private var gain: (change: Decimal, line: String)? {
        guard let first = call.calls.first, first.action != "buy",
            let price = Decimal(engine: first.price), let entry = Decimal(engine: first.entryPrice), entry > 0
        else { return nil }
        let change = (price - entry) / entry
        let percent = change.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
        return (change, L10n.string("%@ on the buy at %@", percent, entry.formatted(.currency(code: "USD"))))
    }

    /// "Waiting 15h 20m", from when the guru posted.
    @MainActor private var waited: String {
        guard let posted = Humanize.date(call.source.sourceAt) else { return L10n.string("Waiting") }
        let minutes = max(0, Int(now.timeIntervalSince(posted) / 60))
        let span =
            minutes < 60
            ? L10n.string("%lldm", Int64(minutes))
            : L10n.string("%lldh %lldm", Int64(minutes / 60), Int64(minutes % 60))
        return L10n.string("Waiting %@", span)
    }

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    message
                    actions.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center, spacing: 24) {
                    summary.frame(maxWidth: .infinity, alignment: .leading)
                    message.frame(width: 320)
                    actions
                }
            }
        }
        .padding(isCompact ? 16 : 20)
        .background(Palette.ticket, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.ticketEdge, lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Palette.amber.opacity(0.35), lineWidth: 3)
                .padding(-3)
                .opacity(isHighlighted || isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHighlighted)
        .onHover(perform: hover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Call waiting for you"))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            eyebrow
            Button(action: open) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(.rect)
            }
            .buttonStyle(QuietPressButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(L10n.string("Open the original post, interpretation, and account results."))
            .accessibilityIdentifier("needsYou.open")
            if let gain {
                Text(gain.line)
                    .font(DesignTokens.bodyText)
                    .monospacedDigit()
                    .foregroundStyle(gain.change < 0 ? Palette.loss : Palette.gain)
            }
        }
    }

    /// A dot, how long it has waited, and until when it can still be copied.
    private var eyebrow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { eyebrowParts }
            VStack(alignment: .leading, spacing: 2) { eyebrowParts }
        }
        .font(DesignTokens.caption.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var eyebrowParts: some View {
        HStack(spacing: 7) {
            Circle().fill(Palette.amber).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(waited).foregroundStyle(Palette.amber).monospacedDigit()
        }
        .fixedSize()
        if let deadline = call.deadline {
            Text(L10n.string("Copy by %@", TradingDeadlineText.text(deadline, now: now)))
                .foregroundStyle(Palette.tertiaryInk)
                .fontWeight(.medium)
                .fixedSize()
        }
    }

    /// The guru's own words on white, under their monogram and name.
    private var message: some View {
        HStack(alignment: .top, spacing: 10) {
            GuruMonogram(name: guruName ?? "?", size: 28, filled: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    if let guruName {
                        Text(guruName).font(DesignTokens.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                    }
                    Spacer(minLength: 8)
                    Text(Humanize.feedTime(call.source.sourceAt, now: now))
                        .font(DesignTokens.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Text(call.source.readableText())
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.page, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hairline, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button(L10n.string("Skip"), action: skip)
                .buttonStyle(QuietTextButtonStyle())
                .accessibilityIdentifier("needsYou.skip")
            copyButton
        }
        .fixedSize()
    }

    @ViewBuilder private var copyButton: some View {
        let button = Button(
            L10n.string(call.calls.isEmpty ? "Enter Trade…" : call.awaitsApproval ? "Approve…" : "Copy…"),
            action: copy
        )
        .buttonStyle(PageButtonStyle(emphasis: isPrimary ? .prominent : .outlined))
        .disabled(!canCopy)
        .accessibilityIdentifier("needsYou.copy")
        .accessibilityHint(L10n.string("Opens the call to check, then previews the order in each waiting account."))
        if isFirst {
            button.keyboardShortcut(.return, modifiers: .command)
        } else {
            button
        }
    }
}
