import DesktopCore

/// Previewing and confirming the sale of one copied lot.
protocol LotSaleOperations: Sendable {
    func previewLotSale(_ preview: LotSalePreviewRequest) async throws -> LotSalePreview
    func confirmLotSale(_ sale: LotSaleConfirmation) async throws -> LotSaleResult
}

extension EngineActions: LotSaleOperations {}
