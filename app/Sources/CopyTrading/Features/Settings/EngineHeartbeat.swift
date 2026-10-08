import SwiftUI

/// The engine's pulse: a quiet trace, with a bright run sweeping along it while the engine runs.
/// Stopped, the trace lies flat and grey. The sweep rests under Reduce Motion and while the window
/// is in the background, where nobody sees it and it would only cost battery.
struct EngineHeartbeat: View {
    let color: Color
    let isBeating: Bool
    @State private var sweep = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    private var isSweeping: Bool { isBeating && !reduceMotion && controlActiveState != .inactive }

    var body: some View {
        ZStack {
            HeartbeatLine()
                .stroke(color.opacity(isSweeping ? 0.3 : 0.35), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            if isSweeping {
                HeartbeatLine(progress: sweep)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(0.45), radius: 5)
            }
        }
        .onAppear(perform: beat)
        .onChange(of: isSweeping) { beat() }
        .accessibilityHidden(true)
    }

    private func beat() {
        sweep = 0
        guard isSweeping else { return }
        withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
            sweep = 1.22
        }
    }
}
