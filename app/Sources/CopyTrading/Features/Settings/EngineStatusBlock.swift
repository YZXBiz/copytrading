import DesktopCore
import SwiftUI

/// The engine as a framed card, the way the invitations are drawn: its heartbeat on the app's
/// chart paper, a serif line saying how it is, one sentence about what it is doing, and the one
/// control that starts or stops it.
struct EngineStatusBlock: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var isStopped: Bool {
        model.runtimeState == .stopped || model.runtimeState == .failed
    }

    private var isBeating: Bool {
        model.runtimeState == .ready || model.runtimeState == .degraded
    }

    /// The icon's teal while it runs, amber when it needs a look, grey when it is stopped.
    private var pulseColor: Color {
        switch model.runtimeState {
        case .ready, .starting:
            colorScheme == .dark ? Color(red: 0.25, green: 0.88, blue: 0.7) : Color(red: 0.11, green: 0.62, blue: 0.5)
        case .degraded: .orange
        case .stopped, .failed: Palette.tertiaryInk
        }
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
            return L10n.string("Copying is paused, so new posts wait until it resumes.") + handled
        case .failed:
            return L10n.string("Copying stopped on a problem. Activity and Diagnostics say what happened.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EngineHeartbeat(color: pulseColor, isBeating: isBeating)
                .frame(height: 46)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .background { ChartPaperBackdrop(focus: UnitPoint(x: 0.5, y: 0.5), gridSpacing: 22) }
                .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n.string("The engine"))
                        Text(state).italic()
                    }
                    .font(DesignTokens.panelSerif)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.string("Local engine, %@", L10n.string(Humanize.code(model.runtimeState.rawValue))))
                    .accessibilityAddTraits(.isHeader)
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
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 26)
        }
        .background(Palette.panel, in: .rect(cornerRadius: 16, style: .continuous))
        .padding(6)
        .background(Palette.page, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : .black.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 16, y: 5)
        .animation(.smooth(duration: 0.3), value: model.runtimeState)
    }

    @ViewBuilder
    private var control: some View {
        if isStopped {
            Button(L10n.string("Start Engine"), action: model.requestStart)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("settings.startEngine")
        } else {
            Button(L10n.string("Stop Engine"), role: .destructive, action: stopEngine)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.red)
                .disabled(model.runtimeState == .starting)
                .help(L10n.string("Stopping drains work in progress. Orders the broker already accepted may stay open."))
                .accessibilityIdentifier("settings.stopEngine")
        }
    }

    private func stopEngine() {
        Task { await model.stopRuntime() }
    }
}
