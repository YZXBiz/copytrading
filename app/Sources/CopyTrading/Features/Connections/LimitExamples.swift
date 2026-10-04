/// One worked example per account limit, shown behind the "i" beside its name. Each matches
/// what the engine does: per-order caps trim a buy, the holding caps skip it whole.
enum LimitExamples {
    static let maxOrder = """
        Set to **$1,000**. A guru's call would put **$2,500** into NVDA. CopyTrading buys **$1,000** of NVDA \
        instead.
        """
    static let maxSymbol = """
        Set to **$3,000**. This account already holds **$2,500** of NVDA, copied or bought yourself. A new \
        **$1,000** NVDA buy would bring it to $3,500, so that buy is **skipped**. It isn't shrunk to fit.
        """
    static let maxTotal = """
        Set to **$10,000**. Everything this account holds, including stocks you bought yourself and buys \
        still waiting to fill, is worth **$9,500**. A new **$1,000** buy of any stock would go over, so it's \
        **skipped**.
        """
    static let dailyLossCap = """
        Set to **$500**. The account closed yesterday at **$20,000**. Once it drops to **$19,500** today, \
        CopyTrading stops buying until tomorrow. When the guru sells, it still sells.
        """
    static let maxAboveSignal = """
        Set to **1**. The guru buys AAPL at **$200.00**; CopyTrading's buy is a limit order at **$202.00**, \
        so it never pays more (at **0**, exactly $200.00). If the guru later sells at **$210.00** before \
        9:30 or after 16:00 New York time, when only limit orders are allowed, CopyTrading's sell won't go \
        below **$207.90**.
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
        Set to **60**. The guru buys NVDA at **$200.00**, so CopyTrading places a buy that only fills at \
        **$200.00 or less**. The price jumps to **$201** and stays there, so nothing fills. After **60 \
        seconds** CopyTrading cancels the order, so it can't quietly fill an hour later, when the call is \
        old.
        """
}
