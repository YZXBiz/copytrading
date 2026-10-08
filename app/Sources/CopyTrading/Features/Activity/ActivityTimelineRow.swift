import SwiftUI

/// One timed step: its dot on the rail, what happened, when, and how long it took.
struct ActivityTimelineRow: View {
    let row: PostTimeline.Row
    let isLast: Bool

    private var dotColor: Color { row.caution ? .orange : Palette.accent }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(Palette.secondaryInk.opacity(0.25))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(row.caution ? .orange : Palette.ink)
                    Spacer(minLength: 8)
                    if let gap = row.gap {
                        Text(L10n.string("+%@", PostTimeline.duration(gap)))
                            .font(DesignTokens.caption.monospacedDigit())
                            .foregroundStyle(row.slow ? .orange : Palette.tertiaryInk)
                            .help(row.slow ? L10n.string("Slower than expected") : "")
                    }
                    Text(row.at.formatted(AppTime.style(.dateTime.hour().minute().second())))
                        .font(DesignTokens.caption.monospacedDigit())
                        .foregroundStyle(Palette.secondaryInk)
                }
                if let detail = row.detail {
                    Text(detail)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
        .accessibilityElement(children: .combine)
    }
}
