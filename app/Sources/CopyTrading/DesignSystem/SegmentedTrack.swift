import SwiftUI

/// A segmented control: a grey track with the chosen option on a white pill.
struct SegmentedTrack<Option: Hashable & Identifiable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    @ViewBuilder let label: (Option) -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSurface

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    label(option)
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                        .animation(nil, value: selection)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 26)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Palette.page)
                                    .matchedGeometryEffect(id: "selected-segment", in: selectionSurface)
                                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 0.5)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(QuietPressButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.group, in: .capsule)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selection)
        // A container, so a caller's label or identifier names the track and each option keeps its own.
        .accessibilityElement(children: .contain)
    }
}
