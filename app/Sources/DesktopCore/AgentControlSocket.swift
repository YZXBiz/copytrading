import Darwin
import Foundation

/// The process on the other end of an agent connection, for the audit trail.
public struct AgentPeer: Equatable, Sendable {
    public let pid: Int32?
    public let executablePath: String?
}

/// Why the socket answered without asking the engine.
public enum AgentRefusal: Equatable, Sendable {
    case busy
    case invalidRequest
    /// The line is over `maximumLineBytes`; it is answered, never silently dropped.
    case tooLarge
}

public enum AgentControlSocketError: Error, Equatable, LocalizedError, Sendable {
    case pathTooLong
    case unsafeLocation
    case unavailable(errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .pathTooLong:
            "The agent control socket path is too long for a Unix socket."
        case .unsafeLocation:
            "The agent control folder is not a private folder owned by this user."
        case .unavailable(let code):
            "The agent control socket could not be opened (\(code))."
        }
    }
}

/// Serves one JSON line per connection on a Unix socket only the current user can reach.
///
/// The socket lives in a `0700` folder with mode `0600`, and peers owned by another user are
/// dropped. At most `maximumConnections` requests are served at once; each runs on its own
/// thread so a slow client never occupies Swift's cooperative pool.
public final class AgentControlSocket: @unchecked Sendable {
    public typealias Handler = @Sendable (String, AgentPeer) async -> String

    public static let maximumLineBytes = 64 * 1024
    private static let ioTimeoutSeconds = 30

    private let url: URL
    private let maximumConnections: Int
    private let refusal: @Sendable (AgentRefusal) -> String
    private let handler: Handler
    private let lock = NSLock()
    /// Writing end of the running accept thread's wake pipe; closing it stops that thread.
    private var wake: Int32 = -1
    private var active = 0

    public init(
        url: URL,
        maximumConnections: Int = 4,
        refusal: @escaping @Sendable (AgentRefusal) -> String,
        handler: @escaping Handler
    ) {
        self.url = url
        self.maximumConnections = maximumConnections
        self.refusal = refusal
        self.handler = handler
    }

    public func start() throws {
        var address = sockaddr_un()
        let path = Array(url.path.utf8)
        guard path.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw AgentControlSocketError.pathTooLong
        }
        try Self.preparePrivateFolder(url.deletingLastPathComponent())
        try Self.removeStaleSocket(at: url)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AgentControlSocketError.unavailable(errno: errno) }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path)
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        var pipeEnds: [Int32] = [-1, -1]
        guard bound == 0, chmod(url.path, 0o600) == 0, listen(descriptor, 16) == 0,
            fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0,
            pipe(&pipeEnds) == 0
        else {
            let code = errno
            close(descriptor)
            unlink(url.path)
            throw AgentControlSocketError.unavailable(errno: code)
        }
        let (wakeReader, wakeWriter) = (pipeEnds[0], pipeEnds[1])
        // A child that inherited the wake pipe would hold it open, and closing ours would never
        // stop the accept thread.
        for end in [descriptor, wakeReader, wakeWriter] { _ = fcntl(end, F_SETFD, FD_CLOEXEC) }
        lock.withLock { wake = wakeWriter }
        Thread.detachNewThread { [self] in acceptConnections(on: descriptor, wake: wakeReader) }
    }

    /// Stop accepting, then remove the socket so a stopped app is never mistaken for a running one.
    ///
    /// Only the accept thread closes its listener. Closing it here could let a later `start`
    /// reuse the descriptor number while that thread is still about to `accept` on it, and the
    /// old thread would then answer the new socket's clients with the old handler.
    public func stop() {
        let descriptor = lock.withLock {
            let current = wake
            wake = -1
            return current
        }
        guard descriptor >= 0 else { return }
        close(descriptor)
        try? Self.removeStaleSocket(at: url)
    }

    private func acceptConnections(on descriptor: Int32, wake: Int32) {
        defer {
            close(descriptor)
            close(wake)
        }
        while true {
            var ready = [
                pollfd(fd: wake, events: Int16(POLLIN), revents: 0),
                pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0),
            ]
            guard poll(&ready, 2, -1) >= 0 || errno == EINTR else { return }
            if ready[0].revents != 0 { return }
            guard ready[1].revents != 0 else { continue }
            let client = accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == EAGAIN || errno == ECONNABORTED { continue }
                return
            }
            Self.configure(client)
            guard Self.peerIsCurrentUser(client) else {
                close(client)
                continue
            }
            let admitted = lock.withLock {
                guard active < maximumConnections else { return false }
                active += 1
                return true
            }
            guard admitted else {
                Self.writeLine(refusal(.busy), to: client)
                close(client)
                continue
            }
            let peer = Self.peer(of: client)
            Thread.detachNewThread { [self] in
                defer {
                    close(client)
                    lock.withLock { active -= 1 }
                }
                switch Self.readLine(from: client) {
                case .line(let line):
                    Self.writeLine(answer(line, from: peer), to: client)
                case .tooLarge:
                    Self.writeLine(refusal(.tooLarge), to: client)
                    // Read what the client still sends, so it gets the answer rather than a reset.
                    Self.drain(client)
                case .invalid:
                    Self.writeLine(refusal(.invalidRequest), to: client)
                }
            }
        }
    }

    /// Wait on this connection's own thread for the async handler's answer.
    private func answer(_ line: String, from peer: AgentPeer) -> String {
        let result = AnswerBox()
        let done = DispatchSemaphore(value: 0)
        let handler = handler
        Task {
            result.set(await handler(line, peer))
            done.signal()
        }
        done.wait()
        return result.value
    }

    private static func preparePrivateFolder(_ folder: URL) throws {
        if mkdir(folder.path, 0o700) != 0, errno != EEXIST {
            throw AgentControlSocketError.unavailable(errno: errno)
        }
        var info = stat()
        guard lstat(folder.path, &info) == 0,
            info.st_mode & S_IFMT == S_IFDIR,
            info.st_uid == getuid(),
            chmod(folder.path, 0o700) == 0
        else {
            throw AgentControlSocketError.unsafeLocation
        }
    }

    private static func removeStaleSocket(at url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else {
            throw AgentControlSocketError.unsafeLocation
        }
        unlink(url.path)
    }

    private static func configure(_ client: Int32) {
        // A connection inherits the listener's non-blocking flag; its reads wait, with a timeout.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var enabled: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: ioTimeoutSeconds, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, size)
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, size)
    }

    private static func peerIsCurrentUser(_ client: Int32) -> Bool {
        var uid = uid_t()
        var gid = gid_t()
        return getpeereid(client, &uid, &gid) == 0 && uid == getuid()
    }

    private static func peer(of client: Int32) -> AgentPeer {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0, pid > 0 else {
            return AgentPeer(pid: nil, executablePath: nil)
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let written = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = written > 0 ? String(decoding: buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
        return AgentPeer(pid: pid, executablePath: path)
    }

    private enum LineRead {
        case line(String)
        case tooLarge
        case invalid
    }

    /// One newline-terminated UTF-8 line within the size limit.
    private static func readLine(from client: Int32) -> LineRead {
        var line = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while line.count <= maximumLineBytes {
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else { return .invalid }
            if let newline = chunk[..<count].firstIndex(of: 10) {
                line.append(contentsOf: chunk[..<newline])
                guard line.count <= maximumLineBytes else { return .tooLarge }
                return String(data: line, encoding: .utf8).map(LineRead.line) ?? .invalid
            }
            line.append(contentsOf: chunk[..<count])
        }
        return .tooLarge
    }

    /// Reads and drops the rest of an oversized request, up to its newline, a few times the limit,
    /// or the read timeout, whichever comes first.
    private static func drain(_ client: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        var total = 0
        while total < maximumLineBytes * 16 {
            let count = read(client, &chunk, chunk.count)
            guard count > 0, !chunk[..<count].contains(10) else { return }
            total += count
        }
    }

    private static func writeLine(_ text: String, to client: Int32) {
        var data = Data(text.utf8)
        data.append(10)
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = write(client, buffer.baseAddress! + offset, buffer.count - offset)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }
}

private final class AnswerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = ""

    var value: String { lock.withLock { stored } }

    func set(_ answer: String) {
        lock.withLock { stored = answer }
    }
}
