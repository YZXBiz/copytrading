import DesktopCore

/// The lot a Sell sheet is open for, in the account it belongs to.
struct LotSaleTarget: Identifiable {
    let accountID: String
    let environment: TradingEnvironment
    let symbol: String
    let lot: AccountLotView
    /// Whose post bought it, for the sheet's title line.
    let guruName: String?
    var id: String { "\(accountID):\(lot.lotID)" }
}
