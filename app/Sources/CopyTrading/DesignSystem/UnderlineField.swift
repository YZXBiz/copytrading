import SwiftUI

/// A native text field with no box, on a `WritingLine`: dotted at rest, solid ink while typing.
/// Typing, focus, and the field's accessibility stay the system's.
struct UnderlineField: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(DesignTokens.bodyText)
            .focused($isFocused)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                WritingLine(isActive: isFocused)
            }
    }
}

extension View {
    /// The sheets' text field: native, borderless, on a writing line.
    func underlineField() -> some View {
        modifier(UnderlineField())
    }
}
