import DesktopCore
import SwiftUI

/// The local engine, written like a page: what it is doing in a sentence, the route every post
/// travels with each stop's state, and the self-test that walks that route without real keys.
struct EngineSettingsPage: View {
    let model: AppModel

    private var engineRunning: Bool {
        model.runtimeState == .ready || model.runtimeState == .degraded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            EngineStatusBlock(model: model)

            VStack(alignment: .leading, spacing: 20) {
                heading(
                    "The Way a Post Travels",
                    "Every post stops at each of these in turn. A stop that is not ready holds the posts behind it.")
                RouteLine(stops: postStops)
            }

            VStack(alignment: .leading, spacing: 8) {
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
                        .disabled(model.isRunningSelfTest || model.pendingCommandID != nil)
                        .accessibilityIdentifier("system.runSelfTest")
                }
                Text(selfTestSentence)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(selfTestAccessibility)
                RouteLine(stops: selfTestStops)
                    .padding(.top, 12)
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
        guard engineRunning else {
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
                    ? L10n.string("%@ waiting", status.pendingSignals.formatted()) : L10n.string("Clear"),
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
        guard let result = model.latestSelfTest else {
            return L10n.string(
                "Sends a fixed local message through capture, reading, and two test destinations. It uses no keys and never places an order."
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
        guard let result = model.latestSelfTest else { return selfTestSentence }
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
