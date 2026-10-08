import DesktopCore
import SwiftUI

/// The engine on the page itself: a line saying how it is, one sentence about what it is doing,
/// the one control that starts or stops it, and the walker on its ground while it runs.
struct EngineStatusBlock: View {
    let model: AppModel

    private var isStopped: Bool {
        model.runtimeState == .stopped || model.runtimeState == .failed
    }

    private var isBeating: Bool {
        model.runtimeState == .ready || model.runtimeState == .degraded
    }

    private var state: String {
        switch model.runtimeState {
        case .ready: L10n.string("is running")
        case .starting: L10n.string("is starting")
        case .degraded: L10n.string("needs a look")
        case .stopped: L10n.string("is stopped")
        case .failed: L10n.string("stopped unexpectedly")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("The engine"))
                    Text(state).foregroundStyle(Palette.tertiaryInk)
                }
                .font(DesignTokens.panelTitle)
                .foregroundStyle(Palette.ink)
                .contentTransition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(L10n.string("Local engine, %@", L10n.string(Humanize.code(model.runtimeState.rawValue))))
                Spacer(minLength: 12)
                control
                    .padding(.top, 6)
            }
            Text(sentence)
                .font(DesignTokens.documentBody)
                .foregroundStyle(Palette.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            InkGround(height: 56)
                .overlay(alignment: .bottomLeading) {
                    if isBeating {
                        InkWalker()
                            .padding(.leading, 60)
                            .padding(.bottom, 3)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 6)
        }
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
