import SwiftUI

/// A compact row of choices for the chart: the selected one sits on a quiet inset.
struct EquityChartPicker<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: String
    let identifier: String
    let title: (Option) -> String
    let spokenTitle: (Option) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSurface
    @State private var hovered: Option?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(DesignTokens.caption.weight(.medium))
                        .foregroundStyle(option == selection ? Palette.ink : Palette.tertiaryInk)
                        .animation(nil, value: selection)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 36, minHeight: 26)
                        .background {
                            if option == selection {
                                Capsule().fill(Palette.page)
                                    .matchedGeometryEffect(id: "choice", in: selectionSurface)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 0.5)
                            } else if hovered == option {
                                Capsule().fill(Palette.hover)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(QuietPressButtonStyle())
                .onHover { hovered = $0 ? option : nil }
                .accessibilityLabel(spokenTitle(option))
                .accessibilityAddTraits(option == selection ? .isSelected : [])
                .help(spokenTitle(option))
            }
        }
        .padding(2)
        .background(Palette.group, in: .capsule)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: selection)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string(label))
        .accessibilityIdentifier(identifier)
    }
}
