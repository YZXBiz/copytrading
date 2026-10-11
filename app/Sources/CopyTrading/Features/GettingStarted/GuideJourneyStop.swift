/// One stop on a post's journey: the diagram's symbol, short title and example call, and the card
/// under it that says what happens there, where to change it, and the one thing to keep in mind.
struct GuideJourneyStop: Hashable {
    let symbol: String
    let title: String
    let example: String
    let headline: String
    let gist: String
    let setting: String
    /// Where the setting lives; nil is the owner's account page.
    let screen: AppModel.Screen?
    let caution: String

    var placeTitle: String { screen?.title ?? "Your account" }

    /// One SOUN call followed from the guru's post to the sale, with numbers that add up under the
    /// default limits: 1/6 of a $600 full position is $100, the most one order spends, which buys
    /// 17 shares at $5.85.
    static let all = [
        GuideJourneyStop(
            symbol: "bubble.left.fill", title: "Guru posts", example: "1/6 SOUN at 5.85",
            headline: "A guru posts", gist: "Every post in your channels, the moment it arrives.",
            setting: "Channels and gurus", screen: .connections,
            caution: "Your Mac must be awake, with CopyTrading open."),
        GuideJourneyStop(
            symbol: "sparkles", title: "AI reads", example: "Buy SOUN $5.85",
            headline: "The AI reads it", gist: "Turned into an exact call: the stock and the price.",
            setting: "Each guru's playbook, drafted by Learn", screen: .connections,
            caution: "An \"if\", a range or no price waits for you."),
        GuideJourneyStop(
            symbol: "gauge.with.needle", title: "Limits check", example: "1/6 of $600",
            headline: "Your limits check it", gist: "Sized as the guru's share of your max per stock.",
            setting: "Every limit, per account", screen: .connections,
            caution: "New accounts start with entries off."),
        GuideJourneyStop(
            symbol: "paperplane.fill", title: "Order fills", example: "17 at $5.85",
            headline: "The order goes to Alpaca", gist: "A limit order, never above the guru's price plus your allowance.",
            setting: "Price allowance and order timeout", screen: .connections,
            caution: "Unfilled by the order timeout, it's cancelled."),
        GuideJourneyStop(
            symbol: "checkmark.seal.fill", title: "You see it", example: "In your account",
            headline: "You see what happened", gist: "Every post ends with an outcome and its reason.",
            setting: "Copy or skip a waiting call until its day ends", screen: nil,
            caution: "Each account decides on its own."),
        GuideJourneyStop(
            symbol: "arrow.uturn.backward", title: "Guru sells", example: "Half at 6.40",
            headline: "When the guru sells", gist: "That part is sold, at no less than their price less your allowance.",
            setting: "Copy exits, or sell any lot yourself", screen: nil,
            caution: "Never your own shares, and no stop-loss of its own."),
    ]
}
