import SwiftUI

/// What the start card says about the setup right now, in the order a person would care.
struct SetupChangesStatus: Equatable {
    /// A few words: "You changed the setup".
    let text: String
    /// One quiet line on what happens next, when the headline needs it.
    let detail: String?
    let symbol: String
    let tone: StatusTone
    let isWorking: Bool

    @MainActor
    init(_ model: AppModel) {
        let problems = model.setupCheckProblemCount
        if model.isValidatingTrading {
            self.init("Checking every connection…", working: true)
        } else if model.isApplyingChanges && !model.isShowingSetupCheck {
            self.init("Applying your changes…", working: true)
        } else if model.isActivatingTrading || model.isConfirmingActivation {
            // Only while a start is under way: sent, or waiting for the engine to confirm it. A setup
            // that passed its check and waits for Start Copying is not starting.
            self.init("Saving and starting…", working: true)
        } else if model.tradingStatus == nil && (model.runtimeState == .stopped || model.runtimeState == .failed) {
            self.init("The engine is stopped", "Start it, then start copying.", "stop.circle.fill", .inactive)
        } else if model.tradingStatus == nil {
            self.init("Starting CopyTrading…", working: true)
        } else if problems == 1 {
            self.init("One check needs attention", "Review it, then start again.", "exclamationmark.triangle.fill", .caution)
        } else if problems > 1 {
            // Every row Setup Check marks Needs attention is counted, so the two always agree.
            self.init(
                text: L10n.string("%lld checks need attention", problems), detail: L10n.string("Review them, then start again."),
                symbol: "exclamationmark.triangle.fill", tone: .caution)
        } else if model.canStartCopyingFromCheck {
            self.init("Everything checks out", "Start copying when you're ready.", "checkmark.circle.fill", .positive)
        } else if model.awaitsExampleReview {
            self.init("Everything checks out", "Look over how the examples were read.", "text.magnifyingglass", .neutral)
        } else if model.tradingStatus?.state != .paused && model.isCopyingSavedSetup {
            // Applying restarts copying; posts from those few seconds wait and are copied after.
            self.init(
                "You changed the setup",
                "Click Apply Changes to use it. Copying restarts in a few seconds, and any post sent meanwhile is still copied.",
                "pencil.circle.fill", .neutral)
        } else if model.tradingStatus?.state != .paused {
            self.init("You changed the setup", "Click Start Copying to use it.", "pencil.circle.fill", .neutral)
        } else if model.savedTradingConfiguration == nil {
            self.init("Ready to start", "Every connection is checked first.", "info.circle.fill", .neutral)
        } else {
            self.init("You have unsaved changes", "Starting checks and saves them.", "pencil.circle.fill", .neutral)
        }
    }

    @MainActor private init(
        _ text: String, _ detail: String? = nil, _ symbol: String = "", _ tone: StatusTone = .neutral, working: Bool = false
    ) {
        self.init(
            text: L10n.string(text), detail: detail.map { L10n.string($0) }, symbol: symbol, tone: tone, isWorking: working)
    }

    private init(text: String, detail: String?, symbol: String, tone: StatusTone, isWorking: Bool = false) {
        self.text = text
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
        self.isWorking = isWorking
    }
}
