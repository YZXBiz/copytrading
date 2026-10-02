import SwiftUI

/// Everything depends on the local engine, so a stopped engine is said once, with the fix beside it.
struct EngineStoppedBanner: View {
    let model: AppModel

    private var isStopped: Bool {
        model.runtimeState == .stopped || model.runtimeState == .failed
    }

    var body: some View {
        if isStopped {
            HStack(spacing: 10) {
                Image(systemName: model.runtimeState == .failed ? "xmark.octagon.fill" : "pause.circle.fill")
                    .foregroundStyle(model.runtimeState == .failed ? .red : .secondary)
                    .accessibilityHidden(true)
                Text(
                    model.runtimeState == .failed
                        ? L10n.string("The local engine stopped because of an error. Nothing is being copied.")
                        : L10n.string("The local engine is stopped. Nothing is being copied."))
                Spacer(minLength: 8)
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
