import SwiftUI

/// An inline notice. Neutral callouts explain; caution and critical ones demand attention.
struct Callout: View {
    let text: String
    var tone: StatusTone = .neutral

    init(_ text: String, tone: StatusTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(tone == .neutral ? Color.secondary : Color.primary)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: tone == .neutral ? "info.circle" : tone.symbol)
                .foregroundStyle(tone == .neutral ? Color.secondary : tone.color)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (tone == .neutral ? Color.secondary : tone.color).opacity(0.08),
            in: .rect(cornerRadius: DesignTokens.calloutCornerRadius)
        )
    }
}
