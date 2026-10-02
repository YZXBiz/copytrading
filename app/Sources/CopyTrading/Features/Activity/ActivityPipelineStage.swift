import SwiftUI

/// One stop on a post's trip through CopyTrading, with the engine's status in words and a tone.
struct ActivityPipelineStage: View {
    let title: String
    let code: String
    var detail: String?

    private var tone: StatusTone { StatusTone(code: code) }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: tone.symbol)
                .font(.system(size: 16))
                .foregroundStyle(tone.color)
                .frame(width: 26, height: 26)
                .background(Palette.page, in: .circle)
            VStack(spacing: 2) {
                Text(title)
                    .font(DesignTokens.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(L10n.string(Humanize.code(code)))
                    .font(DesignTokens.caption)
                    .foregroundStyle(tone == .positive ? Palette.secondaryInk : tone.color)
                if let detail {
                    Text(detail)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
