import DesktopCore
import SwiftUI

/// The local engine, written like a page: what it is doing in a sentence with the route every post
/// travels right under it, then the self-test that walks a practice post through without keys.
struct EngineSettingsPage: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            VStack(alignment: .leading, spacing: 22) {
                EngineStatusBlock(model: model)
                // The route under the sentence it explains: where a post is now held, it shows.
                RouteLine(stops: postStops)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    heading("Self-Test", nil)
                    Spacer(minLength: 12)
                    if model.pendingCommandID != nil {
                        Button(L10n.string("Retry Pending Self-Test"), action: retry)
                            .buttonStyle(.borderless)
                            .disabled(model.isRunningSelfTest)
                    }
                    Button(L10n.string(model.isRunningSelfTest ? "Running…" : "Run Self-Test"), action: run)
                        .buttonStyle(PageButtonStyle())
                        .disabled(!model.isEngineRunning || model.isRunningSelfTest || model.pendingCommandID != nil)
                        .accessibilityIdentifier("system.runSelfTest")
                }
                Text(selfTestSentence)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(selfTestAccessibility)
                selfTestSteps
            }
        }
    }

    /// The test's three steps on one quiet line, each with its own dot: "● Captured  ● Read  ○ Delivered".
    private var selfTestSteps: some View {
        HStack(spacing: 18) {
            ForEach(selfTestStops) { stop in
                HStack(spacing: 6) {
                    ToneDot(tone: stop.tone, size: 9)
                    Text(L10n.string(stop.title))
                        .font(DesignTokens.caption.weight(stop.needsLook ? .semibold : .regular))
                        .foregroundStyle(stop.tone == .inactive ? Palette.tertiaryInk : Palette.ink)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.string("%@, %@", L10n.string(stop.title), L10n.string(stop.state)))
            }
        }
    }

    private func heading(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(title))
                .font(DesignTokens.settingsHeading)
                .tracking(DesignTokens.listHeadingTracking)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(L10n.string(subtitle))
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The way a post travels

    private var postStops: [RouteStop] {
        let waiting = model.savedTradingConfiguration == nil ? "Not set up" : "Waiting"
        guard model.isEngineRunning else {
            return [
                .init(title: "Discord", state: waiting, tone: .inactive),
                .init(title: "Interpreter", state: waiting, tone: .inactive),
                .init(title: "Risk checks", state: "Engine stopped", tone: .inactive),
                .init(title: "Accounts", state: waiting, tone: .inactive),
            ]
        }
        guard let status = model.tradingStatus else {
            return [
                .init(title: "Discord", state: waiting, tone: .inactive),
                .init(title: "Interpreter", state: waiting, tone: .inactive),
                .init(title: "Risk checks", state: "Ready", tone: .positive),
                .init(title: "Accounts", state: waiting, tone: .inactive),
            ]
        }
        let accountsTone: StatusTone =
            status.configuredAccounts == 0 ? .inactive : status.activeAccounts == status.configuredAccounts ? .positive : .caution
        return [
            .init(
                title: "Discord", state: status.sourceConnected ? "Connected" : "Not connected",
                tone: status.sourceConnected ? .positive : .caution),
            .init(
                title: "Interpreter", state: status.modelReady ? "Ready" : "Not ready",
                tone: status.modelReady ? .positive : .caution),
            .init(
                title: "Risk checks",
                state: status.pendingSignals > 0
                    ? L10n.string("%@ waiting", status.pendingSignals.formatted()) : L10n.string("Nothing waiting"),
                tone: status.pendingSignals > 0 ? .neutral : .positive),
            .init(
                title: "Accounts",
                state: status.configuredAccounts == 0
                    ? L10n.string("None yet")
                    : L10n.string("%@ of %@ copying", status.activeAccounts.formatted(), status.configuredAccounts.formatted()),
                tone: accountsTone),
        ]
    }

    // MARK: Self-test

    private var selfTestSentence: String {
        if model.isRunningSelfTest { return L10n.string("Sending the test message through now…") }
        guard model.isEngineRunning else { return L10n.string("Start the engine to run the self-test.") }
        guard let result = model.latestSelfTest else {
            return L10n.string(
                "Sends a practice post through every step. It uses no keys and never places an order."
            )
        }
        switch result.stage {
        case .completed:
            return L10n.string(
                "The last run went all the way through: captured, read, and delivered to %@.",
                Humanize.count(result.outcomes.count, "test destination")
            )
        case .failed:
            return L10n.string("The last run stopped before it was delivered. Diagnostics has the details.")
        case .captured, .parsed:
            return L10n.string("The last run is still on its way through.")
        }
    }

    private var selfTestAccessibility: String {
        guard model.isEngineRunning, let result = model.latestSelfTest else { return selfTestSentence }
        return L10n.string(
            "Last result, %@. %@",
            L10n.string(Humanize.code(result.stage.rawValue)),
            selfTestSentence
        )
    }

    private var selfTestStops: [RouteStop] {
        func stop(_ title: String, _ order: Int) -> RouteStop {
            if model.isRunningSelfTest { return .init(title: title, state: "Running", tone: .neutral) }
            guard let stage = model.latestSelfTest?.stage else { return .init(title: title, state: "Not run yet", tone: .inactive) }
            if stage == .failed { return .init(title: title, state: "Failed", tone: .critical) }
            let reached: Int =
                switch stage {
                case .captured: 1
                case .parsed: 2
                case .completed: 3
                case .failed: 0
                }
            return reached >= order
                ? .init(title: title, state: "Done", tone: .positive) : .init(title: title, state: "Not reached", tone: .inactive)
        }
        return [stop("Captured", 1), stop("Read", 2), stop("Delivered", 3)]
    }

    private func run() {
        Task { await model.runSelfTest() }
    }

    private func retry() {
        Task { await model.retryPendingSelfTest() }
    }
}
