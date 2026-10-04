/// One worked example per account limit, shown behind the "i" beside its name. Each matches
/// what the engine does: per-order caps trim a buy, the holding caps skip it whole.
enum LimitExamples {
    static let maxOrder = """
        Set to **$1,000**. A guru's call would put **$2,500** into NVDA. CopyTrading buys **$1,000** of NVDA \
        instead.
        """
    static let maxSymbol = """
        Set to **$3,000**. You already hold **$2,500** of NVDA from earlier calls. A new **$1,000** NVDA buy \
        would bring it to $3,500, so that buy is **skipped**. It isn't shrunk to fit.
        """
    static let maxTotal = """
        Set to **$10,000**. The stocks CopyTrading bought in this account are worth **$9,500** together. A \
        new **$1,000** buy of any stock would go over, so it's **skipped**.
        """
    static let dailyLossCap = """
        Set to **$500**. The account closed yesterday at **$20,000**. Once it drops to **$19,500** today, \
        CopyTrading stops buying until tomorrow. When the guru sells, it still sells.
        """
    static let maxAboveSignal = """
        Set to **1**. The guru buys AAPL at **$200.00**. CopyTrading's buy is a limit order at **$202.00**, \
        so it never pays more. At **0** the limit is **$200.00** exactly. Outside regular hours, a copied \
        sell also won't go below **$198.00**.
        """
    static let entriesPerDay = """
        Set to **5**. After the fifth copied buy today, the next buy calls are skipped until the next \
        trading day. Sells still go through.
        """
    static let maxSignalAge = """
        Set to **120**. A guru posts *Buy NVDA* at **9:31:00**. If CopyTrading gets that post, or is about \
        to send its order, after **9:33:00** (your Mac was asleep, or Discord was slow), it skips it as *Too \
        old to copy*. You can still copy it yourself from **Activity** with **Review and Correct**.
        """
    static let orderTimeout = """
        Set to **60**. A limit buy at **$200.00** sits unfilled because the price moved to **$201**. After \
        **60 seconds** CopyTrading cancels it, so it can't fill later at a moment you didn't expect.
        """
    static let pollInterval = """
        Set to **5**. CopyTrading asks Alpaca every **5 seconds** whether orders filled and what the balance \
        is. Lower is fresher; higher sends fewer requests.
        """
}
