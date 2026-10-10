import DesktopCore
import Foundation

/// The lot a Sell sheet is open for, in the account it belongs to.
struct LotSaleTarget: Identifiable {
    let accountID: String
    let environment: TradingEnvironment
    let symbol: String
    let lot: AccountLotView
    /// Whose post bought it, for the sheet's title line.
    let guruName: String?
    /// The account asks to approve every order, so a sale needs Touch ID even on paper (ADR-0008).
    var approvesOrders = false
    /// Today's price of the symbol, for the sheet's live preview before the broker is asked.
    var currentPrice: Decimal?
    var id: String { "\(accountID):\(lot.lotID)" }
    /// A live account always asks for Touch ID; a paper one only when it asked to approve orders.
    var asksForOwner: Bool { environment == .live || approvesOrders }
}
