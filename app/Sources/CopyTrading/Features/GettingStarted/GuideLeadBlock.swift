import SwiftUI

/// The guide's opening paragraph in a soft grey block.
struct GuideLeadBlock: View {
    var body: some View {
        Text(
            localizedMarkdown(
                "Think of CopyTrading as a careful assistant for your trading Discord. It watches the **gurus** you choose, turns each call into an exact order, checks it against **limits you set**, and places it in your **paper** or **live** account — then shows you exactly what happened. Nothing is saved or traded until you choose Start Copying, and it checks everything first."
            )
        )
        .font(DesignTokens.documentBody)
        .foregroundStyle(Palette.ink)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.group, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
    }
}
