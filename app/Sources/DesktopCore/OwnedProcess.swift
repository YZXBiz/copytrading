import Darwin
import Foundation

enum OwnedProcessEvent: Sendable {
    case terminated(Int32)
}

actor OwnedProcess: EngineTransport {
    nonisolated let events: AsyncStream<OwnedProcessEvent>
    nonisolated let generation = UUID()

    private let specification: ProcessLaunchSpecification
    private let outputBufferLimit: Int
    private let process = Process()
    private let standardInput = Pipe()
    private let standardOutput = Pipe()
    private let standardError = Pipe()
    private let eventContinuation: AsyncStream<OwnedProcessEvent>.Continuation
    private var outputTail = Data()
    private var errorTail = Data()
    private var hasExited = false
    private var stderrDidFinish = false
    private var observedTerminationStatus: Int32?

    init(specification: ProcessLaunchSpecification, outputBufferLimit: Int) {
        let (events, continuation) = AsyncStream<OwnedProcessEvent>.makeStream()
        self.events = events
        eventContinuation = continuation
        self.specification = specification
        self.outputBufferLimit = outputBufferLimit
    }

    func start() throws {
        process.executableURL = specification.executableURL
        process.arguments = specification.arguments
        process.environment = specification.environment
        process.currentDirectoryURL = specification.workingDirectory
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { await self?.didTerminate(status) }
        }
        let errorHandle = standardError.fileHandleForReading
        Task.detached { [weak self] in
            do {
                while let chunk = try readPipeChunk(errorHandle) {
                    await self?.appendError(chunk)
                }
            } catch {
                await self?.didFinishStderr()
                return
            }
            await self?.didFinishStderr()
        }
        if !specification.stdoutIsIPC {
            let outputHandle = standardOutput.fileHandleForReading
            Task.detached { [weak self] in
                do {
                    while let chunk = try readPipeChunk(outputHandle) {
                        await self?.appendOutput(chunk)
                    }
                } catch {
                    return
                }
            }
        }
        do {
            try process.run()
        } catch {
            try? standardInput.fileHandleForWriting.close()
            try? standardOutput.fileHandleForWriting.close()
            try? standardError.fileHandleForWriting.close()
            throw ProcessSupervisorError.startupFailed
        }
        try? standardInput.fileHandleForReading.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
    }

    func send(_ line: Data) throws {
        guard process.isRunning else { throw ProcessSupervisorError.startupFailed }
        guard line.last == 10, (process.standardInput as? Pipe) === standardInput else {
            throw EngineTransportError.malformedResponse
        }
        let inputWriter = standardInput.fileHandleForWriting
        try inputWriter.write(contentsOf: line)
    }

    func responseLines() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let outputHandle = standardOutput.fileHandleForReading
            Task.detached {
                var line = Data()
                do {
                    while let chunk = try readPipeChunk(outputHandle) {
                        for byte in chunk {
                            if byte == 10 {
                                continuation.yield(line)
                                line.removeAll(keepingCapacity: true)
                            } else {
                                line.append(byte)
                                if line.count > 1_048_576 {
                                    throw EngineTransportError.responseTooLarge
                                }
                            }
                        }
                    }
                    if !line.isEmpty { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func isRunning() -> Bool {
        process.isRunning
    }

    func processIdentifier() -> Int32? {
        process.isRunning ? process.processIdentifier : nil
    }

    func stderrTail() -> String {
        String(decoding: errorTail, as: UTF8.self)
    }

    func stdoutTail() -> String {
        String(decoding: outputTail, as: UTF8.self)
    }

    @discardableResult
    func stop(gracePeriod: Duration = .seconds(3)) async -> Bool {
        try? standardInput.fileHandleForWriting.close()
        guard process.isRunning else { return false }
        process.terminate()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: gracePeriod)
        while process.isRunning && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let exitedGracefully = !process.isRunning
        if !exitedGracefully {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        while process.isRunning {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return exitedGracefully
    }

    private func didTerminate(_ status: Int32) {
        guard observedTerminationStatus == nil else { return }
        observedTerminationStatus = status
        finishTerminationIfReady()
    }

    private func didFinishStderr() {
        stderrDidFinish = true
        finishTerminationIfReady()
    }

    private func finishTerminationIfReady() {
        guard !hasExited, stderrDidFinish, let status = observedTerminationStatus else { return }
        hasExited = true
        eventContinuation.yield(.terminated(status))
        eventContinuation.finish()
    }

    private func appendError(_ chunk: Data) {
        errorTail.append(chunk)
        trim(&errorTail)
    }

    private func appendOutput(_ chunk: Data) {
        outputTail.append(chunk)
        trim(&outputTail)
    }

    private func trim(_ data: inout Data) {
        guard data.count > outputBufferLimit else { return }
        data.removeFirst(data.count - outputBufferLimit)
    }
}

private func readPipeChunk(_ handle: FileHandle, maximumSize: Int = 16_384) throws -> Data? {
    var buffer = Data(count: maximumSize)
    while true {
        let count = buffer.withUnsafeMutableBytes { bytes in
            Darwin.read(handle.fileDescriptor, bytes.baseAddress, bytes.count)
        }
        if count >= 0 {
            guard count > 0 else { return nil }
            buffer.count = count
            return buffer
        }
        if errno != EINTR {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
