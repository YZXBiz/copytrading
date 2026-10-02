import SwiftUI

/// One stage of a post's trip in the guide's opening figure: a white card with a numbered caption.
struct GuideFlowCard<Content: View>: View {
    let number: Int
    let caption: String
    let isLit: Bool
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(Palette.page, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isLit ? Palette.accent.opacity(0.7) : Palette.hairline, lineWidth: isLit ? 1.5 : 1)
            }
            .shadow(color: Palette.accent.opacity(isLit ? 0.18 : 0), radius: 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isLit)
            HStack(spacing: 6) {
                StepNumber(number: number)
                Text(L10n.string(caption))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}
