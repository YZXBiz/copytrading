import Foundation
import Testing

@testable import DesktopCore

/// Answers the first request with a reply the app cannot read and every later one with the
/// shared status fixture, each carrying the request's own identifier.
private actor UnreadableThenStatusTransport: EngineTransport {
    private let statusFixture: [String: Any]
    private let stream: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private var sent = 0

    init(statusFixture: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: statusFixture) as? [String: Any] else {
            throw VerificationFailure(description: "the status fixture is not an object")
        }
        self.statusFixture = object
        (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    }

    func send(_ line: Data) throws {
        guard let request = try JSONSerialization.jsonObject(with: line) as? [String: Any],
            let requestID = request["request_id"] as? String
        else { throw VerificationFailure(description: "the request carried no identifier") }
        sent += 1
        var reply = statusFixture
        reply["request_id"] = requestID
        if sent == 1 { reply["ok"] = ["type": "a_result_this_app_has_never_heard_of"] }
        continuation.yield(try JSONSerialization.data(withJSONObject: reply))
    }

    func responseLines() -> AsyncThrowingStream<Data, any Error> { stream }
}

@Test func anUnreadableReplyFailsOnlyTheRequestItAnswers() async throws {
    let transport = try UnreadableThenStatusTransport(
        statusFixture: contractFixture("status-response.json")
    )
    let client = EngineClient(transport: transport, requestTimeout: .seconds(5))

    await #expect(throws: EngineTransportError.malformedResponse) {
        _ = try await client.status()
    }
    // The engine is answering; the next request must get its reply, not wait out the deadline.
    let status = try await client.status()
    #expect(status.state == .running)
}
