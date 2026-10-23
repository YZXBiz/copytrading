import DesktopCore

/// Why a `copytrading setup …` request changed nothing: a contract error code, and a sentence
/// that names the account or guru, what happened, and what to do. It never holds a key.
struct AgentSetupProblem: Error, Equatable {
    let code: String
    let message: String

    static func invalid(_ message: String) -> AgentSetupProblem {
        AgentSetupProblem(code: "invalid_request", message: message)
    }

    static func notFound(_ message: String) -> AgentSetupProblem {
        AgentSetupProblem(code: "not_found", message: message)
    }

    static func conflict(_ message: String) -> AgentSetupProblem {
        AgentSetupProblem(code: "conflict", message: message)
    }

    static let locked = AgentSetupProblem(code: "locked", message: "Unlock CopyTrading first.")

    static let engineNotRunning = AgentSetupProblem(
        code: "unavailable",
        message: "The CopyTrading engine isn't running. Start it in Settings → Engine, then try again.")

    /// Asking the engine failed: not running, too slow, or an answer this app can't read.
    static func engineProblem(_ error: any Error) -> AgentSetupProblem {
        switch error {
        case EngineTransportError.requestTimedOut:
            AgentSetupProblem(
                code: "unavailable",
                message:
                    "The CopyTrading engine didn't answer in time, so nothing changed. Try again in a moment; if it keeps happening, restart the engine in Settings → Engine."
            )
        case is EngineContractError, is DecodingError:
            AgentSetupProblem(
                code: "unavailable",
                message:
                    "The CopyTrading engine answered in a way this app can't read, so nothing changed. Quit and reopen CopyTrading so the app and its engine match."
            )
        default:
            engineNotRunning
        }
    }

    static let busy = AgentSetupProblem(
        code: "busy",
        message: "CopyTrading is checking or starting the setup. Wait for it to finish, then try again.")
}
