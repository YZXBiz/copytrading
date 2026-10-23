import DesktopCore
import Foundation

/// A trading status the engine could report, built with sensible defaults so a test states only
/// what it is about (a Test Data Builder: *AI Driven Swift Architecture*, ch. 4).
public struct TradingStatusBuilder {
    private var state: TradingRunState
    private var accounts = 0
    private var ready = false
    private var errorCode: String?
    private var accountStates: [(id: String, state: String, errorCode: String?)] = []

    public init(_ state: TradingRunState = .paused) {
        self.state = state
    }

    /// One account, with Discord and the model connected.
    public func connected() -> Self {
        var copy = self
        copy.accounts = 1
        copy.ready = true
        return copy
    }

    /// An account the engine reports in this state: "running", "failed", or "paused", with the
    /// reason a failed one gives.
    public func account(_ id: String, _ state: String, error: String? = nil) -> Self {
        var copy = self
        copy.accountStates.append((id, state, error))
        return copy
    }

    public func error(_ code: String?) -> Self {
        var copy = self
        copy.errorCode = code
        return copy
    }

    public func build() throws -> TradingStatus {
        let payload: [String: Any] = [
            "state": state.rawValue, "configured_accounts": accounts, "active_accounts": accounts,
            "source_connected": ready, "model_ready": ready, "pending_source": 0,
            "pending_signals": 0, "processed_signals": 0, "error_code": errorCode ?? NSNull(),
            "accounts": accountStates.map {
                ["id": $0.id, "state": $0.state, "error_code": $0.errorCode ?? NSNull()] as [String: Any]
            },
        ]
        return try JSONDecoder().decode(TradingStatus.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
