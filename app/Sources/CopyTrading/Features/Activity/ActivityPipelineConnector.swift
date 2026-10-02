import SwiftUI

/// The line into a pipeline stop: solid once the post reached it, faint while it has not.
struct ActivityPipelineConnector: View {
    let code: String

    private var isReached: Bool { StatusTone(code: code) != .inactive }

    var body: some View {
        Capsule()
            .fill(isReached ? Palette.secondaryInk.opacity(0.35) : Palette.hairline)
            .frame(height: 2)
            .padding(.top, 12)
            .frame(maxWidth: 80)
            .accessibilityHidden(true)
    }
}
