import SwiftUI

/// Everything depends on the local engine, so a stopped engine is said once, with the fix beside it.
struct EngineStoppedBanner: View {
    let model: AppModel

    private var isStopped: Bool {
        model.runtimeState == .stopped || model.runtimeState == .failed
    }

    /// Why nothing is copied. Another copy of the app holding the engine's data is named, since
    /// it is the usual reason a local build's engine can't start.
    private var message: String {
        if model.runtimeState == .failed, OtherAppCopy.running != nil {
            return L10n.string("Another copy of CopyTrading is open and has the engine. Quit it, then start the engine here.")
        }
        return model.runtimeState == .failed
            ? L10n.string("The local engine stopped because of an error. Nothing is being copied.")
            : L10n.string("The local engine is stopped. Nothing is being copied.")
    }

    var body: some View {
        if isStopped {
            HStack(spacing: 10) {
                Image(systemName: model.runtimeState == .failed ? "xmark.octagon.fill" : "pause.circle.fill")
                    .foregroundStyle(model.runtimeState == .failed ? .red : .secondary)
                    .accessibilityHidden(true)
                Text(message)
                Spacer(minLength: 8)
                if let other = OtherAppCopy.running {
                    Button(L10n.string("Quit the Other Copy")) { other.terminate() }
                        .accessibilityIdentifier("engine.quitOtherCopy")
                }
                Button(L10n.string("Start Engine"), action: model.requestStart)
                    .accessibilityIdentifier("engine.start")
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.canvas)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}
