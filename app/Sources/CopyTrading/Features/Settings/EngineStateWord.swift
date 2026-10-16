/// The engine's state in one word, the same on the Engine page and to VoiceOver.
enum EngineStateWord {
    /// `needsLook` is a problem holding posts back while the engine itself runs.
    @MainActor
    static func word(_ state: AppModel.RuntimeState, needsLook: Bool) -> String {
        switch state {
        case .ready: needsLook ? L10n.string("Needs a look") : L10n.string("Running")
        case .starting: L10n.string("Starting")
        case .degraded: L10n.string("Needs a look")
        case .stopped: L10n.string("Stopped")
        case .failed: L10n.string("Stopped unexpectedly")
        }
    }

    /// What VoiceOver reads for the heading: the word on screen, after what it describes.
    @MainActor
    static func spoken(_ state: AppModel.RuntimeState, needsLook: Bool) -> String {
        L10n.string("Local engine, %@", word(state, needsLook: needsLook))
    }
}
