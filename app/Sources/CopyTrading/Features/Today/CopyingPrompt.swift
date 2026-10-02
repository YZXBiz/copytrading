import SwiftUI

/// While copying is off, say so where the money is, with the switch beside it.
struct CopyingPrompt: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Pill(text: "Copying paused", symbol: "pause.circle.fill", tint: .orange)
        }
    }
}
