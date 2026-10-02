import Darwin
import DesktopCore
import Foundation

private func shortStateRoot() throws -> URL {
    // Unix socket paths are limited to 104 bytes, so test roots keep short names.
    let root = FileManager.default.temporaryDirectory
        .appending(path: "ct-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// Send one line the way the `copytrading` client does and return the single answer line.
private func exchange(_ line: String, at socketURL: URL) throws -> String {
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

    func append(_ context: AgentRequestContext) { lock.withLock { contexts.append(context) } }
    var all: [AgentRequestContext] { lock.withLock { contexts } }
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
            recorded.append(context)
            if line.contains("fail") { throw EngineTransportError.disconnected }
            return #"{"echo":"# + line + "}"
        }
    )
    try relay.start()

    var folder = stat()
    var entry = stat()
    try verify(
        lstat(socketURL.deletingLastPathComponent().path, &folder) == 0
            && folder.st_mode & 0o777 == 0o700, "the agent folder must be owner-only")
    try verify(
        lstat(socketURL.path, &entry) == 0 && entry.st_mode & S_IFMT == S_IFSOCK
            && entry.st_mode & 0o777 == 0o600, "the agent socket must be owner-only")

    let answer = try await Task.detached { try exchange(#"{"hello":1}"#, at: socketURL) }.value
    try verify(answer == #"{"echo":{"hello":1}}"#, "the relay must pass the engine's line back unchanged")
    let context = recorded.all.first
    try verify(
        context?.accessLevel == .readAndPause && context?.unlocked == false,
        "the relay must send the owner's access level and lock state")
    try verify(
        context?.callerPID == getpid() && context?.callerPath?.isEmpty == false,
        "the relay must identify the calling process for the audit trail")

    let unavailable = try await Task.detached { try exchange("fail", at: socketURL) }.value
    let unavailableCode = try errorCode(of: unavailable)
    try verify(
        unavailableCode == "unavailable",
        "an engine failure must become a contract error, not a dropped connection")

    let oversized = String(repeating: "x", count: AgentControlSocket.maximumLineBytes + 10)
    let refused = try await Task.detached { try exchange(oversized, at: socketURL) }.value
    let refusedCode = try errorCode(of: refused)
    try verify(refusedCode == "invalid_request", "oversized lines must be refused")

    relay.stop()
    try verify(
        !FileManager.default.fileExists(atPath: socketURL.path),
        "stopping must remove the socket so clients see the app as not running")

    try relay.start()
    relay.stop()

    try runAgentSocketLimitTests(root: root)
}

private func runAgentSocketLimitTests(root: URL) throws {
    let socketURL = AgentRelay.socketURL(stateRoot: root)
    let gate = Gate()
    let busy = AgentControlSocket(
        url: socketURL,
        maximumConnections: 1,
        refusal: { _ in #"{"error":{"code":"busy"}}"# },
        handler: { _, _ in
            while !gate.isOpen { try? await Task.sleep(for: .milliseconds(20)) }
            return "done"
        }
    )
    try busy.start()
    let first = Thread.detachNewThreadWithResult { try? exchange("one", at: socketURL) }
    Thread.sleep(forTimeInterval: 0.3)
    let second = try exchange("two", at: socketURL)
    try verify(
        second == #"{"error":{"code":"busy"}}"#,
        "requests beyond the connection cap must be refused as busy")
    gate.open()
    try verify(first.wait() == "done", "the admitted request must still be answered")
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

    var isOpen: Bool { lock.withLock { opened } }

    func open() { lock.withLock { opened = true } }
}

extension Thread {
    fileprivate final class Result<Value: Sendable>: @unchecked Sendable {
        private let done = DispatchSemaphore(value: 0)
        private var value: Value?

        func finish(_ result: Value?) {
            value = result
            done.signal()
        }

        func wait() -> Value? {
            done.wait()
            return value
        }
    }

    fileprivate static func detachNewThreadWithResult<Value: Sendable>(
        _ body: @escaping @Sendable () -> Value?
    ) -> Result<Value> {
        let result = Result<Value>()
        detachNewThread { result.finish(body()) }
        return result
    }
}

private struct CLIResult {
    let status: Int32
    let output: String
    let errorOutput: String
}

/// Run the real `copytrading` client, as an agent would, against the relay's state root.
private func runCLI(
    _ arguments: [String], python: URL, pythonPath: String, stateRoot: URL
) async throws -> CLIResult {
    try await Task.detached {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
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
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CLIResult(
            status: process.terminationStatus, output: String(decoding: data, as: UTF8.self),
            errorOutput: String(decoding: errorData, as: UTF8.self))
    }.value
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
    let relay = AgentRelay(
        socketURL: AgentRelay.socketURL(stateRoot: root),
        accessLevel: .propose,
        isUnlocked: { lockSwitch.isUnlocked },
        send: { line, context in try await actions.control(line: line, context: context) }
    )
    do {
        try await supervisor.start()
        try relay.start()
        let cli = { (arguments: [String]) in
            try await runCLI(arguments, python: python, pythonPath: pythonPath, stateRoot: root)
        }

        let status = try await cli(["status", "--json"])
        if status.status != 0 {
            // Tell a client-side failure from a relay or engine one: ask the relay directly.
            let socketURL = AgentRelay.socketURL(stateRoot: root)
            let exists = FileManager.default.fileExists(atPath: socketURL.path)
            let direct = await Task.detached { (try? exchange(#"{"hello":1}"#, at: socketURL)) ?? "no answer" }.value
            FileHandle.standardError.write(
                Data("relay socket \(socketURL.path) exists=\(exists); direct answer: \(direct)\n".utf8))
        }
        try verify(
            status.status == 0 && status.output.contains(#""engine_state":"running""#),
            "the CLI must read engine status through the app relay: exit \(status.status), \(status.output) \(status.errorOutput)")

        let resume = try await cli(["accounts", "resume", "nobody"])
        try verify(resume.status == 6, "the engine must refuse to propose for an unknown account")

        lockSwitch.set(unlocked: false)
        let locked = try await cli(["accounts"])
        try verify(locked.status == 4, "reads must wait for the owner to unlock the app")
        let paused = try await cli(["pause", "--json"])
        try verify(
            paused.status == 0 && paused.output.contains(#""type":"processing""#),
            "pausing must work even while the app is locked")

        let discarded = try await actions.discardProposals()
        try verify(discarded == 0, "locking with nothing waiting must discard nothing")

        relay.stop()
        let stopped = try await cli(["status"])
        try verify(stopped.status == 3, "a stopped relay must read as not running")
        await supervisor.stop()
    } catch {
        relay.stop()
        await supervisor.stop()
        throw error
    }
}
