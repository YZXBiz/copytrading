import SwiftUI

/// A one-point rule in the hairline grey, across or, with `vertical`, up and down.
struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}
