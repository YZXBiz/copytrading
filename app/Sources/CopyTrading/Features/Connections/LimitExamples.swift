import Foundation

/// One worked example per account limit, shown behind the "i" beside its name, in short plain
/// sentences. Each matches what the engine does (ADR-0010): every limit cuts a buy to what it
/// allows, and only the shares CopyTrading bought count.
enum LimitExamples {
    static let maxOrder = """
        Set to **$1,000**. The guru's call would buy **$2,500** of NVDA, or the post is misread as \
        that much. You buy **$1,000**. A call that gives no size buys **$1,000** too.
        """
    static let maxSymbol = """
        Set to **$3,000**. CopyTrading holds **$2,500** of NVDA. A **$1,000** NVDA buy is cut to \
        **$500**, the room left. NVDA shares you bought yourself don't count.
        """
    static let maxTotal = """
        Set to **$10,000**. CopyTrading holds **$9,500** in all. A new **$1,000** buy is cut to \
        **$500**, the room left.
        """
    static let dailyLossCap = """
        Set to **$500**. The account closed yesterday at **$20,000**. If it drops to **$19,500** \
        today, buying stops until tomorrow. Sells still go through.
        """
    static let maxAboveSignal = """
        Set to **1**. The guru buys AAPL at **$200**. You pay **$202** at most. At **0**, you pay \
        **$200** at most.
        """
    static let maxBelowSignal = """
        Set to **1**. The guru sells AAPL at **$200**. When CopyTrading sells, AAPL is at **$190**. \
        You sell at **$188.10** or better, so a sell read late still gets out.
        """
    static let entriesPerDay = """
        Set to **5**. After 5 buys today, more buys are skipped until tomorrow. Sells still go \
        through.
        """
    static let maxSignalAge = """
        Set to **600**. The guru posts a buy at **9:31**. If it reaches CopyTrading after **9:41** \
        (say your Mac was asleep), it isn't copied; you can copy it yourself in **Activity**. A sell \
        is copied whenever it arrives.
        """
    /// The order timeout, priced with this account's own tolerance above the guru's price, so the
    /// example never disagrees with the setting just above it.
    @MainActor
    static func orderTimeout(maxAboveSignalPct: String) -> String {
        let percent = Decimal(string: maxAboveSignalPct.trimmingCharacters(in: .whitespaces)) ?? 0
        var ceiling = Decimal(200) * (1 + max(percent, 0) / 100)
        var limit = Decimal()
        NSDecimalRound(&limit, &ceiling, 2, .down)
        var above = limit + 3
        var jump = Decimal()
        NSDecimalRound(&jump, &above, 0, .up)
        return L10n.string(
            """
            Set to **60**. The guru buys NVDA at **$200.00**. With **Maximum above signal price** at **%@%%**, \
            your buy fills at **%@ or less**. The price jumps to **%@** and stays there, so nothing fills. \
            After **60 seconds** the order is cancelled, so it can't fill hours later.
            """,
            percent.formatted(),
            limit.formatted(.currency(code: "USD").precision(.fractionLength(2))),
            jump.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        )
    }
}
