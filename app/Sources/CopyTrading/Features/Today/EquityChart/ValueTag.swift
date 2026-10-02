import SwiftUI

/// A tag on the value axis: the latest or inspected value on its gain or loss color, or a quiet reference.
struct ValueTag: View {
    let text: String
    let color: Color
    var textColor: Color = .white

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: .rect(cornerRadius: 4))
            .fixedSize()
    }
}
