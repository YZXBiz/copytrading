import SwiftUI

/// One settings row: an optional small grey label, the name or value, an
/// optional grey line under it, and a control at the trailing edge.
struct SettingsRow<Trailing: View>: View {
    var label: String?
    let title: String
    var detail: String?
    var tone: StatusTone?
    var titleColor = Palette.ink
    /// The trailing control is named by these words and hinted with the detail, so VoiceOver
    /// reads them once, on the control, instead of once as text and again on the control.
    var labelsControl = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                if let label {
                    Text(L10n.string(label))
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                        .accessibilityHidden(labelsControl)
                }
                HStack(spacing: 6) {
                    if let tone {
                        Image(systemName: tone.symbol)
                            .imageScale(.small)
                            .foregroundStyle(tone.color)
                            .accessibilityHidden(true)
                    }
                    Text(L10n.string(title))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(titleColor)
                        .textSelection(.enabled)
                        .accessibilityHidden(labelsControl)
                }
                if let detail {
                    Text(L10n.string(detail))
                        .font(.body)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(labelsControl)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

extension SettingsRow where Trailing == EmptyView {
    /// A reading with nothing to change: VoiceOver hears the label and the value together.
    init(label: String? = nil, title: String, detail: String? = nil, tone: StatusTone? = nil, titleColor: Color = Palette.ink) {
        self.init(label: label, title: title, detail: detail, tone: tone, titleColor: titleColor) { EmptyView() }
    }
}
