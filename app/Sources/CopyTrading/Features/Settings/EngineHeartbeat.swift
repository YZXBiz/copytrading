import SwiftUI

/// The engine's pulse, drawn still: a bright trace with a soft glow while the engine runs, a faint
/// grey one when it is stopped.
struct EngineHeartbeat: View {
    let color: Color
    let isBeating: Bool

    var body: some View {
        HeartbeatLine()
            .stroke(
                color.opacity(isBeating ? 1 : 0.35),
                style: StrokeStyle(lineWidth: isBeating ? 2 : 1.6, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: color.opacity(isBeating ? 0.35 : 0), radius: 5)
            .accessibilityHidden(true)
    }
}
