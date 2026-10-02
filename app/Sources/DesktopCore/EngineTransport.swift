import Foundation

public protocol EngineTransport: Actor {
    func send(_ line: Data) throws
    func responseLines() -> AsyncThrowingStream<Data, any Error>
}

public enum EngineTransportError: Error, Equatable, LocalizedError, Sendable {
    case requestTooLarge
    case responseTooLarge
    case disconnected
    case malformedResponse
    case requestTimedOut

    public var errorDescription: String? {
        switch self {
        case .requestTooLarge:
            "The engine request exceeded the local protocol limit."
        case .responseTooLarge:
            "The engine response exceeded the local protocol limit."
        case .disconnected:
            "The local engine disconnected."
        case .malformedResponse:
            "The local engine returned an invalid response."
        case .requestTimedOut:
            "The local engine did not answer before the request deadline."
        }
    }
}
