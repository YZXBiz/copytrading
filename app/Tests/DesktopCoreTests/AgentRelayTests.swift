import Darwin
import DesktopCore
import Foundation
import Testing

private func shortStateRoot() throws -> URL {
    // Unix socket paths are limited to 104 bytes, so test roots keep short names.
    let root = FileManager.default.temporaryDirectory
        .appending(path: "ct-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// Send one line the way the `copytrading` client does and return the single answer line.
/// One request and its answer, on a thread of its own: the socket read blocks, and blocking a
/// cooperative thread can leave the relay's handler no thread to answer on.
private func exchange(_ line: String, at socketURL: URL) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        Thread.detachNewThread {
            continuation.resume(with: Result { try exchangeBlocking(line, at: socketURL) })
        }
    }
}

private func exchangeBlocking(_ line: String, at socketURL: URL) throws -> String {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw VerificationFailure(description: "client socket failed") }
    defer { close(descriptor) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = Array(socketURL.path.utf8)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { throw VerificationFailure(description: "client could not connect") }
    let request = Array((line + "\n").utf8)
    guard write(descriptor, request, request.count) == request.count else {
        throw VerificationFailure(description: "client could not send")
    }
    var answer = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while !answer.contains(10) {
        let count = read(descriptor, &buffer, buffer.count)
        guard count > 0 else { break }
        answer.append(contentsOf: buffer[..<count])
    }
    return String(decoding: answer, as: UTF8.self).trimmingCharacters(in: .newlines)
}

private func errorCode(of line: String) throws -> String? {
    let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    return (object?["error"] as? [String: Any])?["code"] as? String
}

private final class Recorded: @unchecked Sendable {
    private let lock = NSLock()
    private var contexts: [AgentRequestContext] = []
    private var received: [String] = []

    func append(_ context: AgentRequestContext, line: String = "") {
        lock.withLock {
            contexts.append(context)
            received.append(line)
        }
    }
    var all: [AgentRequestContext] { lock.withLock { contexts } }
    var lines: [String] { lock.withLock { received } }
}

func runAgentRelayTests() async throws {
    let root = try shortStateRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let socketURL = AgentRelay.socketURL(stateRoot: root)
    let recorded = Recorded()
    let relay = AgentRelay(
        socketURL: socketURL,
        accessLevel: .readAndPause,
        isUnlocked: { false },
        send: { line, context in
            recorded.append(context, line: line)
            if line.contains("fail") { throw EngineTransportError.disconnected }
            return #"{"echo":"# + line + "}"
        }
    )
    try relay.start()

    var folder = stat()
    var entry = stat()
    try #require(
        lstat(socketURL.deletingLastPathComponent().path, &folder) == 0
            && folder.st_mode & 0o777 == 0o700, "the agent folder must be owner-only")
    try #require(
        lstat(socketURL.path, &entry) == 0 && entry.st_mode & S_IFMT == S_IFSOCK
            && entry.st_mode & 0o777 == 0o600, "the agent socket must be owner-only")

    let answer = try await exchange(#"{"hello":1}"#, at: socketURL)
    try #require(answer == #"{"echo":{"hello":1}}"#, "the relay must pass the engine's line back unchanged")
    let context = recorded.all.first
    try #require(
        context?.accessLevel == .readAndPause && context?.unlocked == false,
        "the relay must send the owner's access level and lock state")
    try #require(
        context?.callerPID == getpid() && context?.callerPath?.isEmpty == false,
        "the relay must identify the calling process for the audit trail")

    let unavailable = try await exchange("fail", at: socketURL)
    let unavailableCode = try errorCode(of: unavailable)
    try #require(
        unavailableCode == "unavailable",
        "an engine failure must become a contract error, not a dropped connection")

    let oversized = String(repeating: "x", count: AgentControlSocket.maximumLineBytes + 10)
    let refused = try await exchange(oversized, at: socketURL)
    let refusedCode = try errorCode(of: refused)
    try #require(refusedCode == "invalid_request", "oversized lines must be refused")
    try #require(refused.contains("too large"), "an oversized line must be told it is too large: \(refused)")

    let setupLine = #"{"schema_version":1,"request_id":"s1","operation":"edit_setup_discord","token":"never-to-the-engine"}"#
    let unanswered = try await exchange(setupLine, at: socketURL)
    let unansweredCode = try errorCode(of: unanswered)
    try #require(unansweredCode == "unavailable", "a relay without a setup handler must refuse setup requests")
    try #require(
        !recorded.lines.contains { $0.contains("never-to-the-engine") }, "a setup request's key must never reach the engine")

    relay.stop()
    try #require(
        !FileManager.default.fileExists(atPath: socketURL.path),
        "stopping must remove the socket so clients see the app as not running")

    let answered = Recorded()
    let setupRelay = AgentRelay(
        socketURL: socketURL,
        accessLevel: .propose,
        setupChanges: true,
        isUnlocked: { true },
        send: { line, context in
            recorded.append(context, line: line)
            return #"{"engine":true}"#
        },
        setup: { line, context in
            answered.append(context, line: line)
            return #"{"app":true}"#
        }
    )
    try setupRelay.start()
    let fromApp = try await exchange(setupLine, at: socketURL)
    try #require(fromApp == #"{"app":true}"#, "a setup request must be answered by the app")
    try #require(
        answered.all.first?.accessLevel == .propose && answered.all.first?.unlocked == true
            && answered.all.first?.setupChanges == true,
        "the app's setup handler must get the owner's access level and lock state")
    let fromEngine = try await exchange(#"{"operation":"get_status"}"#, at: socketURL)
    try #require(fromEngine == #"{"engine":true}"#, "every other request must still go to the engine")
    try #require(
        !recorded.lines.contains { $0.contains("never-to-the-engine") }, "a setup request's key must never reach the engine")
    setupRelay.stop()

    try relay.start()
    relay.stop()

    try await runAgentSocketLimitTests(root: root)
}

private func runAgentSocketLimitTests(root: URL) async throws {
    let socketURL = AgentRelay.socketURL(stateRoot: root)
    let gate = Gate()
    let busy = AgentControlSocket(
        url: socketURL,
        maximumConnections: 1,
        refusal: { _ in #"{"error":{"code":"busy"}}"# },
        handler: { _, _ in
            gate.arrive()
            while !gate.isOpen { try? await Task.sleep(for: .milliseconds(20)) }
            return "done"
        }
    )
    try busy.start()
    let first = Task { try? await exchange("one", at: socketURL) }
    // "two" must find the one connection taken, so wait until "one" holds it rather than for a
    // fixed time: on a loaded runner "one" can connect late and "two" would take the slot.
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !gate.hasArrived, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    try #require(gate.hasArrived, "the first request never reached the handler")
    let second = try await exchange("two", at: socketURL)
    try #require(
        second == #"{"error":{"code":"busy"}}"#,
        "requests beyond the connection cap must be refused as busy")
    gate.open()
    try #require(await first.value == "done", "the admitted request must still be answered")
    busy.stop()

    FileManager.default.createFile(atPath: socketURL.path, contents: Data("not a socket".utf8))
    try verifyThrows(
        { try busy.start() },
        matching: { ($0 as? AgentControlSocketError) == .unsafeLocation },
        "a plain file at the socket path must never be replaced"
    )
    try FileManager.default.removeItem(at: socketURL)

    let deep = root.appending(path: String(repeating: "d", count: 120), directoryHint: .isDirectory)
    let tooLong = AgentControlSocket(
        url: deep.appending(path: "cli.sock"), refusal: { _ in "" }, handler: { _, _ in "" }
    )
    try verifyThrows(
        { try tooLong.start() },
        matching: { ($0 as? AgentControlSocketError) == .pathTooLong },
        "an over-long socket path must be refused"
    )
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var arrived = false

    var isOpen: Bool { lock.withLock { opened } }
    var hasArrived: Bool { lock.withLock { arrived } }

    func open() { lock.withLock { opened = true } }
    func arrive() { lock.withLock { arrived = true } }
}

private struct CLIResult {
    let status: Int32
    let output: String
    let errorOutput: String
}

/// Run the real `copytrading` client, as an agent would, against the relay's state root.
///
/// The client blocks until it exits, so it waits on its own thread: the relay answers it from
/// Swift's cooperative pool, which has only a few threads on a small machine.
private func runCLI(
    _ arguments: [String], python: URL, pythonPath: String, stateRoot: URL, input: String = ""
) async throws -> CLIResult {
    try await withCheckedThrowingContinuation { continuation in
        Thread.detachNewThread {
            continuation.resume(
                with: Result {
                    try runCLIBlocking(
                        arguments, python: python, pythonPath: pythonPath, stateRoot: stateRoot, input: input)
                })
        }
    }
}

private func runCLIBlocking(
    _ arguments: [String], python: URL, pythonPath: String, stateRoot: URL, input: String
) throws -> CLIResult {
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    let standardInput = Pipe()
    process.standardInput = standardInput
    process.executableURL = python
    process.arguments = ["-m", "copytrading_engine.control"] + arguments
    process.environment = [
        "PATH": "/usr/bin:/bin",
        "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        "PYTHONPATH": pythonPath,
        "PYTHONDONTWRITEBYTECODE": "1",
        "COPYTRADING_STATE_ROOT": stateRoot.path,
    ]
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    standardInput.fileHandleForWriting.write(Data(input.utf8))
    try standardInput.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CLIResult(
        status: process.terminationStatus, output: String(decoding: data, as: UTF8.self),
        errorOutput: String(decoding: errorData, as: UTF8.self))
}

/// Stands in for the app's setup handler: it asks the real engine, then answers as the app does.
private func answerSetup(
    _ line: String, context: AgentRequestContext, actions: EngineActions, received: Recorded
) async -> String {
    let request: AgentSetupRequest
    do {
        request = try AgentSetupRequest(line: line)
    } catch {
        return AgentSetupResponse.errorLine(requestID: error.requestID, code: "invalid_request", message: error.message)
    }
    if case .discord(let discord) = request.edit { received.append(context, line: discord.token?.value ?? "") }
    let facts = request.operation == .apply ? AgentSetupApplyFacts(madeLive: ["live-1"], startsLive: ["live-1"]) : nil
    let authorization = try? await actions.authorizeSetup(
        AgentSetupAuthorizationRequest(operation: request.operation, requestID: request.requestID, apply: facts),
        context: context)
    switch authorization {
    case .answered(let answer):
        return answer
    case .allowed:
        let view = AgentSetupView(
            saved: true, unsavedChanges: true, copying: "paused",
            discord: .init(channelIDs: ["111"], authorIDs: [], token: .entered, check: nil),
            model: .init(service: "deepseek", model: "deepseek-flash", baseURL: nil, key: .saved, check: nil),
            accounts: [], gurus: [], alerts: .init(enabled: false, service: .telegram, chatID: nil, token: .missing, check: nil))
        return AgentSetupResponse.line(requestID: request.requestID, result: .setup(view))
    case nil:
        return AgentSetupResponse.errorLine(requestID: request.requestID, code: "unavailable", message: "engine")
    }
}

private final class LockSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var unlocked = true

    var isUnlocked: Bool { lock.withLock { unlocked } }

    func set(unlocked value: Bool) { lock.withLock { unlocked = value } }
}

func runAgentControlEngineTests() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let runtimePath = environment["COPYTRADING_RUNTIME_ROOT"],
        let enginePath = environment["COPYTRADING_ENGINE_ROOT"],
        let libraryPath = environment["COPYTRADING_PYTHON_LIBRARY_PATH"]
    else {
        FileHandle.standardError.write(Data("SKIP agent control with the engine: paths are unset\n".utf8))
        return
    }
    let root = try shortStateRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dataDirectory = root.appending(path: "data", directoryHint: .isDirectory)
    let diagnostics = root.appending(path: "diagnostics", directoryHint: .isDirectory)
    for directory in [dataDirectory, diagnostics] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let python = try RuntimeResourceCatalog.runtimeManifest().executable(
        named: "cpython", under: URL(filePath: runtimePath, directoryHint: .isDirectory)
    )
    let pythonPath = "\(enginePath)/src:\(libraryPath)"
    let identity = UUID().uuidString.lowercased()
    let supervisor = ProcessSupervisor(
        configuration: ProcessSupervisorConfiguration(
            children: [
                ProcessLaunchSpecification(
                    child: .engine,
                    executableURL: python,
                    arguments: [
                        "-u", "-m", "copytrading_engine", "--data-dir", dataDirectory.path,
                        "--instance-id", identity,
                    ],
                    environment: [
                        "PATH": "/usr/bin:/bin",
                        "PYTHONPATH": pythonPath,
                        "PYTHONUNBUFFERED": "1",
                        "PYTHONDONTWRITEBYTECODE": "1",
                        "COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR": diagnostics.path,
                        "COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR": root.path,
                    ],
                    workingDirectory: root,
                    readiness: .engineStatus(expectedInstanceID: identity),
                    stdoutIsIPC: true
                )
            ],
            maximumRestarts: 0,
            startupTimeout: .seconds(45)
        ))
    let actions = EngineActions(supervisor: supervisor)
    let lockSwitch = LockSwitch()
    let received = Recorded()
    let relay = AgentRelay(
        socketURL: AgentRelay.socketURL(stateRoot: root),
        accessLevel: .propose,
        setupChanges: true,
        isUnlocked: { lockSwitch.isUnlocked },
        send: { line, context in try await actions.control(line: line, context: context) },
        setup: { line, context in await answerSetup(line, context: context, actions: actions, received: received) }
    )
    do {
        try await supervisor.start()
        try relay.start()
        let cli = { (arguments: [String]) in
            try await runCLI(arguments, python: python, pythonPath: pythonPath, stateRoot: root)
        }

        let status = try await cli(["status", "--json"])
        try #require(
            status.status == 0 && status.output.contains(#""engine_state":"running""#),
            "the CLI must read engine status through the app relay: exit \(status.status), \(status.output) \(status.errorOutput)")

        let resume = try await cli(["accounts", "resume", "nobody"])
        try #require(resume.status == 6, "the engine must refuse to propose for an unknown account")

        let token = "token-from-standard-input"
        let discord = try await runCLI(
            ["setup", "discord", "--channels", "111", "--secret-stdin"], python: python, pythonPath: pythonPath,
            stateRoot: root, input: token + "\n")
        try #require(
            discord.status == 0 && discord.output.contains("token entered, not saved yet"),
            "the CLI must change the setup through the app: exit \(discord.status), \(discord.output) \(discord.errorOutput)")
        try #require(received.lines == [token], "the token must reach the app's setup handler from standard input")
        try #require(
            !(discord.output + discord.errorOutput).contains(token), "the CLI must never print the token it sent")
        let live = try await cli(["setup", "apply"])
        try #require(
            live.status == 10 && live.output.contains("makes live-1 live"),
            "applying a live setup must wait for the owner: exit \(live.status), \(live.output) \(live.errorOutput)")
        _ = try await actions.discardProposals()

        lockSwitch.set(unlocked: false)
        let locked = try await cli(["accounts"])
        try #require(locked.status == 4, "reads must wait for the owner to unlock the app")
        let paused = try await cli(["pause", "--json"])
        try #require(
            paused.status == 0 && paused.output.contains(#""type":"processing""#),
            "pausing must work even while the app is locked")

        let discarded = try await actions.discardProposals()
        try #require(discarded == 0, "locking with nothing waiting must discard nothing")

        relay.stop()
        let stopped = try await cli(["status"])
        try #require(stopped.status == 3, "a stopped relay must read as not running")
        await supervisor.stop()
    } catch {
        relay.stop()
        await supervisor.stop()
        throw error
    }
}
