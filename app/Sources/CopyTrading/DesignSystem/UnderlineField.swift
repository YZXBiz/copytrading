import SwiftUI

/// A native text field with no box and no line at rest: the field being typed in gets an ink
/// underline, so the only line is the one that says where the typing goes. Typing, focus, and the field's accessibility stay the system's.
struct UnderlineField: ViewModifier {
    @FocusState private var isFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(DesignTokens.bodyText)
            .foregroundStyle(Palette.ink)
            .focused($isFocused)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isFocused ? Palette.ink : rule)
                    .opacity(isFocused || contrast == .increased ? 1 : 0)
                    .frame(height: isFocused ? 1.5 : 1)
                    .accessibilityHidden(true)
            }
    }

    private var rule: Color {
        contrast == .increased ? Palette.secondaryInk : Palette.hairline
    }
}

extension View {
    /// The sheets' text field: native, borderless, on one underline.
    func underlineField() -> some View {
        modifier(UnderlineField())
    }
}
