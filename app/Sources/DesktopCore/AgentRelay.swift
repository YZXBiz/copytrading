import Foundation

/// Relays agent requests from the `copytrading` CLI and MCP server to the engine.
///
/// The relay adds only what the app knows — the owner's access level, whether the app is
/// unlocked, and the calling process — and passes the engine's answer back unchanged. Every
/// permission rule lives in the engine's `control` package.
public final class AgentRelay: Sendable {
    public typealias Send = @Sendable (String, AgentRequestContext) async throws -> String

    private let socket: AgentControlSocket

    public init(
        socketURL: URL,
        accessLevel: AgentAccessLevel,
        isUnlocked: @escaping @Sendable () async -> Bool,
        send: @escaping Send
    ) {
        socket = AgentControlSocket(
            url: socketURL,
            refusal: { refusal in
                switch refusal {
                case .busy:
                    Self.errorLine(code: "busy", message: "Too many requests; wait a few seconds.")
                case .invalidRequest:
                    Self.errorLine(code: "invalid_request", message: "The request is not valid.")
                }
            },
            handler: { line, peer in
                let context = AgentRequestContext(
                    accessLevel: accessLevel,
                    unlocked: await isUnlocked(),
                    callerPID: peer.pid,
                    callerPath: peer.executablePath
                )
                do {
                    return try await send(line, context)
                } catch {
                    return Self.errorLine(
                        code: "unavailable", message: "The CopyTrading engine is not available."
                    )
                }
            }
        )
    }

    /// The agent socket inside the app's state folder, where the `copytrading` client looks.
    public static func socketURL(stateRoot: URL) -> URL {
        stateRoot.appending(path: "control", directoryHint: .isDirectory).appending(path: "cli.sock")
    }

    public func start() throws {
        try socket.start()
    }

    public func stop() {
        socket.stop()
    }

    /// A contract error response for requests the engine never saw.
    static func errorLine(code: String, message: String) -> String {
        let response = ErrorResponse(error: .init(code: code, message: message))
        guard let data = try? JSONEncoder().encode(response) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct ErrorResponse: Encodable {
    struct Body: Encodable {
        let code: String
        let message: String
    }

    let error: Body

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case ok
        case error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode("", forKey: .requestID)
        try container.encodeNil(forKey: .ok)
        try container.encode(error, forKey: .error)
    }
}
