import SwiftUI

/// A guru's post as it looks in a channel, for the guide's figures.
struct GuidePostSlip: View {
    let name: String
    let time: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GuruMonogram(name: name, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(verbatim: name).font(DesignTokens.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(verbatim: time).font(DesignTokens.caption).foregroundStyle(Palette.tertiaryInk).monospacedDigit()
                }
                Text(L10n.string(text))
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Palette.page, in: .rect(cornerRadius: 10))
    }
}
