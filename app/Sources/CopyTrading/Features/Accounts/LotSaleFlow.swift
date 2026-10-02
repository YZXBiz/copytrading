import DesktopCore
import Foundation
import Observation

/// Selling one lot: choose how many shares, review a fresh preview, confirm once. A live account
/// asks for Touch ID before the sale goes out. The same confirmation ID is reused if the owner
/// retries, so a sale is never placed twice.
@MainActor
@Observable
final class LotSaleFlow {
    enum Phase: Equatable {
        case choosing
        case checking
        case reviewing(LotSalePreview)
        case selling(LotSalePreview)
        case finished(LotSaleResult)
    }

    let target: LotSaleTarget
    var shares: Decimal
    private(set) var phase: Phase = .choosing
    private(set) var problem: String?
    private var commandID = "lot-sale-" + UUID().uuidString.lowercased()

    init(target: LotSaleTarget) {
        self.target = target
        shares = Decimal(engine: target.lot.remainingQty) ?? 0
    }

    var remaining: Decimal { Decimal(engine: target.lot.remainingQty) ?? 0 }

    var canReview: Bool {
        shares > 0 && shares <= remaining && phase != .checking
    }

    func review(using operations: (any LotSaleOperations)?) async {
        guard let operations, canReview else { return }
        problem = nil
        phase = .checking
        let request = LotSalePreviewRequest(
            previewID: "lot-sale-preview-" + UUID().uuidString.lowercased(),
            accountID: target.accountID,
            lotID: target.lot.lotID,
            quantity: NSDecimalNumber(decimal: shares).stringValue
        )
        do {
            phase = .reviewing(try await operations.previewLotSale(request))
        } catch {
            phase = .choosing
            problem = "CopyTrading could not check this sale with the broker. Try again in a moment."
        }
    }

    /// Sends the reviewed sale. `confirmOwner` asks for Touch ID; it runs only for live accounts.
    func confirm(using operations: (any LotSaleOperations)?, confirmOwner: () async throws -> Void) async {
        guard let operations, case .reviewing(let preview) = phase, preview.plan != nil else { return }
        problem = nil
        if target.environment == .live {
            do {
                try await confirmOwner()
            } catch {
                problem = "The sale was not sent: Touch ID was not confirmed."
                return
            }
        }
        phase = .selling(preview)
        let confirmation = LotSaleConfirmation(
            commandID: commandID, previewID: preview.request.previewID, accountID: target.accountID, actor: "owner")
        do {
            phase = .finished(try await operations.confirmLotSale(confirmation))
        } catch {
            phase = .reviewing(preview)
            problem = "CopyTrading could not reach the engine. Your sale may not have been sent; check Accounts before trying again."
        }
    }

    /// After a rejected or expired review, start over with a new sale identity.
    func startOver() {
        commandID = "lot-sale-" + UUID().uuidString.lowercased()
        problem = nil
        phase = .choosing
    }
}
