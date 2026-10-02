import Foundation

enum TradingSettingsError: Error, LocalizedError {
    case invalidConfiguration(String)
    case missingCredentials(String)
    case activationFailed
    case privateAccessLocked
    case engineUnavailable
    case historicalEvaluationUnavailable
    case invalidEvaluationResult

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            reason
        case .missingCredentials(let what):
            "Enter \(what) first."
        case .activationFailed:
            "The engine did not accept the validated trading configuration."
        case .privateAccessLocked:
            "Unlock private activity before evaluating a historical message."
        case .engineUnavailable:
            "Start the local engine before evaluating a historical message."
        case .historicalEvaluationUnavailable:
            "Evaluating an older post needs a saved guru that copies into an account."
        case .invalidEvaluationResult:
            "The engine returned an invalid historical evaluation. No order was submitted."
        }
    }
}
