import SwiftUI

/// What the start card says about the setup right now, in the order a person would care.
struct SetupChangesStatus: Equatable {
    let text: String
    let symbol: String
    let tone: StatusTone
    let isWorking: Bool

    @MainActor
    init(_ model: AppModel) {
        let hasProblem =
            !model.profileExampleReviews.values.allSatisfy(\.automaticActivationAllowed)
            || model.tradingValidation.map { !$0.report.activatable } == true
        if model.isValidatingTrading {
            self.init("Checking every connection…", working: true)
        } else if model.isActivatingTrading || (model.validatedConfiguration != nil && model.tradingStatus?.state != .paused) {
            // Copying can report started before the engine confirms the new setup is the one running.
            self.init("Saving and starting…", working: true)
        } else if model.tradingStatus == nil && (model.runtimeState == .stopped || model.runtimeState == .failed) {
            self.init("The engine is stopped. Start it, then start copying.", "stop.circle.fill", .inactive)
        } else if model.tradingStatus == nil {
            self.init("Starting CopyTrading…", working: true)
        } else if hasProblem {
            self.init(
                "Some checks need attention. Review them, fix the setup, then start again.", "exclamationmark.triangle.fill",
                .caution)
        } else if model.canStartCopyingFromCheck {
            self.init("Everything checks out. Start copying when you're ready.", "checkmark.circle.fill", .positive)
        } else if model.awaitsExampleReview {
            self.init("Everything checks out. Look over how the examples were read.", "text.magnifyingglass", .neutral)
        } else if model.tradingStatus?.state != .paused {
            self.init(
                "Apply Changes pauses copying for a moment, checks the new setup, and copies with it. Posts in between aren't missed.",
                "pencil.circle.fill", .neutral)
        } else if model.savedTradingConfiguration == nil {
            self.init("Ready to start. Every connection is checked first.", "info.circle.fill", .neutral)
        } else {
            self.init("You have changes that aren't saved yet. Starting checks and saves them.", "pencil.circle.fill", .neutral)
        }
    }

    @MainActor private init(_ text: String, _ symbol: String = "", _ tone: StatusTone = .neutral, working: Bool = false) {
        self.text = L10n.string(text)
        self.symbol = symbol
        self.tone = tone
        self.isWorking = working
    }
}
