import Darwin
import Foundation

public struct RecordedSelfTest: Codable, Equatable, Identifiable, Sendable {
    public let command: SelfTestCommand
    public var workflow: WorkflowView?
    public var id: String { command.commandID }
    public var isPending: Bool { workflow == nil || (workflow?.stage != .completed && workflow?.stage != .failed) }
}

public enum CommandJournalError: Error, LocalizedError, Sendable {
    case unavailable
    case conflictingCommand
    case missingCommand

    public var errorDescription: String? {
        switch self {
        case .unavailable: "CopyTrading could not save its local command history. No new self-test was sent."
        case .conflictingCommand: "The command ID is already recorded with different content."
        case .missingCommand: "The workflow has no matching local command envelope."
        }
    }
}

/// App-owned write-ahead envelopes; engine SQLite remains authoritative for accepted workflows.
public actor CommandJournal {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func entries() throws -> [RecordedSelfTest] {
        try read()
    }

    public func record(_ command: SelfTestCommand) throws {
        var values = try read()
        if let existing = values.first(where: { $0.id == command.commandID }) {
            guard existing.command == command else { throw CommandJournalError.conflictingCommand }
            return
        }
        values.append(RecordedSelfTest(command: command, workflow: nil))
        try write(values)
    }

    public func record(_ workflow: WorkflowView) throws {
        var values = try read()
        guard let index = values.firstIndex(where: { $0.id == workflow.commandID }) else {
            throw CommandJournalError.missingCommand
        }
        if let existing = values[index].workflow,
            existing.stage == .completed || existing.stage == .failed
        {
            return
        }
        values[index].workflow = workflow
        try write(values)
    }

    private func read() throws -> [RecordedSelfTest] {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return [] }
            throw CommandJournalError.unavailable
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_size <= 16 * 1024 * 1024 else {
            throw CommandJournalError.unavailable
        }
        do { return try JSONDecoder().decode([RecordedSelfTest].self, from: Data(contentsOf: url)) } catch {
            throw CommandJournalError.unavailable
        }
    }

    private func write(_ values: [RecordedSelfTest]) throws {
        let parent = url.deletingLastPathComponent()
        let temporary = parent.appending(path: ".commands-\(UUID().uuidString).tmp")
        do {
            let bytes = try JSONEncoder().encode(values)
            guard bytes.count <= 16 * 1024 * 1024 else { throw CommandJournalError.unavailable }
            let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw CommandJournalError.unavailable }
            defer { Darwin.close(descriptor) }
            try bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    guard written > 0 else { throw CommandJournalError.unavailable }
                    offset += written
                }
            }
            guard Darwin.fsync(descriptor) == 0, Darwin.rename(temporary.path, url.path) == 0 else {
                throw CommandJournalError.unavailable
            }
            let directoryDescriptor = Darwin.open(parent.path, O_RDONLY)
            guard directoryDescriptor >= 0 else { throw CommandJournalError.unavailable }
            defer { Darwin.close(directoryDescriptor) }
            guard Darwin.fsync(directoryDescriptor) == 0 else { throw CommandJournalError.unavailable }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw CommandJournalError.unavailable
        }
    }
}
