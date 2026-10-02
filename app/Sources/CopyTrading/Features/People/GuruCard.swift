import DesktopCore
import SwiftUI

/// One guru as a framed card in their own color: who they are, their latest call on a slip of
/// paper with what it was understood as, a trail of how their recent posts went, and where their
/// calls are copied, in plain sentences.
struct GuruCard: View {
    let guru: GuruDirectory.Guru
    let stats: GuruStats
    let latest: SourceActivity?
    let isHovered: Bool
    /// Set when the unsaved setup changes this guru, such as removing them.
    var pendingNote: String?
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var previewSize = 15

    private var tint: Color {
        GuruMonogram.tint(for: guru.name).opacity(colorScheme == .dark ? 0.12 : 0.07)
    }

    var body: some View {
        FramedCard(tint: tint, isHovered: isHovered) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    GuruMonogram(name: guru.name, size: 38)
                    Spacer(minLength: 8)
                    if let pendingNote {
                        Pill(text: pendingNote, symbol: "pencil.circle.fill", tint: .orange)
                    } else if !stats.trail.isEmpty {
                        GuruCallTrail(trail: stats.trail)
                            .padding(.top, 6)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(guru.name)
                        .font(DesignTokens.cardSerif.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(lastPostText)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                latestCall
                Text(record)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(copies)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var latestCall: some View {
        if let latest {
            let preview = PeopleSourcePreview.text(for: latest, dropping: guru.prefix)
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    preview.isEmpty
                        ? localizedMarkdown("No message text was captured.")
                        : PeopleSourcePreview.formatted(preview)
                )
                .font(.system(size: previewSize))
                .lineSpacing(3)
                .foregroundStyle(preview.isEmpty ? Palette.secondaryInk : Palette.ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: latest.needsManualReview ? "exclamationmark.bubble" : "arrow.turn.down.right")
                        .imageScale(.small)
                        .foregroundStyle(latest.needsManualReview ? latest.decisionTone.color : Palette.tertiaryInk)
                        .accessibilityHidden(true)
                    Text(latest.headline)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colorScheme == .dark ? Color(white: 0.17) : .white, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        } else {
            Text(L10n.string("Quiet so far. Their next post lands here."))
                .font(.system(.body, design: .serif).italic().scaled(by: 16.0 / 13))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor private var lastPostText: String {
        guard let last = stats.lastPost else { return L10n.string("No posts loaded yet") }
        return L10n.string(
            "Last post %@",
            last.formatted(.relative(presentation: .named).locale(AppLanguagePreference.shared.language.locale))
        )
    }

    /// How their calls went, counted per call rather than per account's order, as one sentence.
    @MainActor private var record: String {
        guard stats.trades > 0 else {
            return stats.posts == 0
                ? L10n.string("No calls yet.")
                : L10n.string("%@, no calls yet.", Humanize.count(stats.posts, "post"))
        }
        var parts = [Humanize.count(stats.trades, "call")]
        parts.append(L10n.string("%@ copied", stats.copiedCalls.formatted()))
        if stats.skippedCalls > 0 { parts.append(L10n.string("%@ skipped", stats.skippedCalls.formatted())) }
        if stats.needsReview > 0 { parts.append(L10n.string("%@ to review", stats.needsReview.formatted())) }
        return parts.joined(separator: " · ")
    }

    @MainActor private var copies: String {
        let accounts = guru.destinations.map(\.accountID)
        switch accounts.count {
        case 0: return L10n.string("Doesn’t copy into an account.")
        case 1: return L10n.string("Copies into %@.", accounts[0])
        default:
            return L10n.string(
                "Copies into %@ and %@.", accounts.dropLast().joined(separator: ", "), accounts.last ?? ""
            )
        }
    }
}
