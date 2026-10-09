import DesktopCore
import SwiftUI

/// The engine on the page itself: one word for how it is beside a status dot, one sentence about
/// what it is doing, and the one control that starts or stops it.
struct EngineStatusBlock: View {
    let model: AppModel

    private var isStopped: Bool {
        model.runtimeState == .stopped || model.runtimeState == .failed
    }

    private var state: (word: String, tone: StatusTone) {
        switch model.runtimeState {
        case .ready: (L10n.string("Running"), .positive)
        case .starting: (L10n.string("Starting"), .inactive)
        case .degraded: (L10n.string("Needs a look"), .caution)
        case .stopped: (L10n.string("Stopped"), .inactive)
        case .failed: (L10n.string("Stopped unexpectedly"), .critical)
        }
    }

    private var sentence: String {
        if isStopped {
            return L10n.string("Nothing is being copied. Orders the broker already accepted may stay open until they fill or expire.")
        }
        if model.runtimeState == .starting { return L10n.string("It takes a few seconds to start on this Mac.") }
        let handled =
            model.engineStatus.map { status in
                let waiting =
                    status.pending > 0
                    ? L10n.string(", and %@ %@ waiting", status.pending.formatted(), L10n.string(status.pending == 1 ? "is" : "are"))
                    : ""
                return status.completed > 0 || status.pending > 0
                    ? L10n.string(" It has handled %@ since it started%@.", Humanize.count(status.completed, "post"), waiting) : ""
            } ?? ""
        guard let trading = model.tradingStatus else {
            return model.savedTradingConfiguration == nil
                ? L10n.string("It is ready for a setup. Nothing is copied until you start copying.")
                : L10n.string("Copying is off, so new posts are not read.") + handled
        }
        switch trading.state {
        case .running, .degraded:
            return L10n.string("CopyTrading is copying new posts into %@.", Humanize.count(trading.activeAccounts, "account")) + handled
        case .starting:
            return L10n.string("Copying is starting: it is connecting to Discord, your interpreter, and your accounts.")
        case .paused, .pausing:
            // Before the first start nothing was ever copying, so nothing is paused.
            guard model.savedTradingConfiguration != nil else {
                return L10n.string("Copying hasn't started yet. Start it from Connections.")
            }
            return L10n.string("Copying is paused, so new posts wait until it resumes.") + handled
        case .failed:
            return L10n.string("Copying stopped on a problem. Activity and Diagnostics say what happened.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(state.tone.color)
                        .frame(width: 8, height: 8)
                    Text(state.word)
                        .font(DesignTokens.listHeading)
                        .tracking(DesignTokens.listHeadingTracking)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(L10n.string("Local engine, %@", L10n.string(Humanize.code(model.runtimeState.rawValue))))
                Spacer(minLength: 12)
                control
            }
            Text(sentence)
                .font(DesignTokens.documentBody)
                .foregroundStyle(Palette.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .animation(.smooth(duration: 0.3), value: model.runtimeState)
    }

    @ViewBuilder
    private var control: some View {
        if isStopped {
            Button(L10n.string("Start Engine"), action: model.requestStart)
                .buttonStyle(PageButtonStyle(isProminent: true))
                .accessibilityIdentifier("settings.startEngine")
        } else {
            Button(L10n.string("Stop Engine"), role: .destructive, action: stopEngine)
                .buttonStyle(PageButtonStyle())
                .disabled(model.runtimeState == .starting)
                .help(L10n.string("Stopping drains work in progress. Orders the broker already accepted may stay open."))
                .accessibilityIdentifier("settings.stopEngine")
        }
    }

    private func stopEngine() {
        Task { await model.stopRuntime() }
    }
}
