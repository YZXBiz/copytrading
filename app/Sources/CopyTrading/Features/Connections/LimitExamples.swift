/// One worked example per account limit, shown behind the "i" beside its name, in short plain
/// sentences. Each matches what the engine does: the per-order limit makes a buy smaller, the
/// holding limits skip it.
enum LimitExamples {
    static let maxOrder = """
        Set to **$1,000**. The guru's call would buy **$2,500** of NVDA. You buy **$1,000** instead.
        """
    static let maxSymbol = """
        Set to **$3,000**. That's the guru's full position, so a 1/6 call buys **$500**. If you \
        already hold **$2,500** of NVDA, a **$1,000** NVDA buy would make $3,500, so it's **skipped**.
        """
    static let maxPriceMove = """
        Set to **5**. The guru buys NVDA at **$200**. If NVDA is now above **$210** or below **$190**, \
        the buy waits in Activity for you to copy or skip.
        """
    static let maxTotal = """
        Set to **$10,000**. You hold **$9,500** in all. A new **$1,000** buy would go over, so it's \
        **skipped**.
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
        Set to **1**. The guru sells AAPL at **$200**. You sell at **$198** or better. At **0**, you \
        sell at **$200** or better.
        """
    static let entriesPerDay = """
        Set to **5**. After 5 buys today, more buys are skipped until tomorrow. Sells still go \
        through.
        """
    static let maxSignalAge = """
        Set to **120**. The guru posts at **9:31:00**. If it reaches CopyTrading after **9:33:00** \
        (say your Mac was asleep), it isn't copied. You can still copy it yourself in **Activity**.
        """
    static let orderTimeout = """
        Set to **60**. The guru buys at **$200**, so your order fills only at $200 or less. If the \
        price stays at **$201**, the order is cancelled after **60 seconds**, so it can't fill hours \
        later.
        """
}
