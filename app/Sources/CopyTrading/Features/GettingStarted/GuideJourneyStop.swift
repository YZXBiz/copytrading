/// One stop on the diagram of a post's journey: its symbol, a short title, and what happens to
/// the example call there.
struct GuideJourneyStop: Hashable {
    let symbol: String
    let title: String
    let example: String

    /// One SOUN call followed from the guru's post to the sale, with numbers that add up: 1/6 of
    /// a $2,000 full position is $333, which buys 56 shares at $5.85.
    static let all = [
        GuideJourneyStop(symbol: "bubble.left.fill", title: "Guru posts", example: "1/6 SOUN at 5.85"),
        GuideJourneyStop(symbol: "sparkles", title: "AI reads", example: "Buy SOUN $5.85"),
        GuideJourneyStop(symbol: "gauge.with.needle", title: "Limits check", example: "1/6 of $2,000"),
        GuideJourneyStop(symbol: "paperplane.fill", title: "Order fills", example: "56 at $5.85"),
        GuideJourneyStop(symbol: "checkmark.seal.fill", title: "You see it", example: "In Activity"),
        GuideJourneyStop(symbol: "arrow.uturn.backward", title: "Guru sells", example: "Half at 6.40"),
    ]
}
