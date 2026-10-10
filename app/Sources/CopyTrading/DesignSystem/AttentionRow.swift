import SwiftUI

/// One thing about an account that needs the owner: a mark that says how it stands, what is wrong
/// in one plain sentence, what waits on it in a quieter line, and the answer beneath. No box, no
/// banner; the mark and the space around the row set it apart.
struct AttentionRow<Actions: View>: View {
    let headline: String
    let detail: String
    var tone: StatusTone = .caution
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            OutcomeMark(tone: tone, size: 13)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(DesignTokens.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                actions
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}
