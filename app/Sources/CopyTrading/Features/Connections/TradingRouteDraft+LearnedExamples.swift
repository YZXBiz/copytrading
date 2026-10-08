import DesktopCore

extension TradingRouteDraft {
    /// Learned examples join the owner's: a post that is already an example is skipped, so
    /// learning again never erases or duplicates what the owner wrote, and the guru never holds
    /// more than the engine accepts. Returns how many were added.
    @discardableResult
    mutating func addLearnedExamples(_ learned: [TradingProfileExample]) -> Int {
        var known = Set(examples.map(\.message.trimmedLines))
        var added = 0
        for example in learned where examples.count < Self.maximumExamples {
            let message = example.message.trimmedLines
            guard !message.isEmpty, known.insert(message).inserted else { continue }
            examples.append(TradingProfileExampleDraft(example: example))
            added += 1
        }
        return added
    }

    /// The most examples a guru's profile may hold (the engine's limit).
    static let maximumExamples = 32
}
