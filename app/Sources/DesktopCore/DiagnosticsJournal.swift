import Foundation

/// One line of the engine's diagnostics journal, shaped for reading.
public struct DiagnosticsJournalEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// A self-test workflow moved to a new stage.
        case stage
        /// A captured source post or model request/response.
        case payload
        /// A trading operation's finite outcome.
        case trading
    }

    /// The record's own time and contents, so a selection survives rereading a growing journal.
    public let id: String
    public let kind: Kind
    public let at: Date
    /// What happened: the stage, payload kind, or trading operation.
    public let name: String
    /// How it ended: an outcome or capture status.
    public let outcome: String
    public let traceID: String?
    public let workflowID: String?
    /// Every recorded field except the payload, sorted by name, as readable text.
    public let fields: [Field]
    /// The redacted payload as indented JSON, when one was captured.
    public let payloadJSON: String?

    public struct Field: Equatable, Sendable {
        public let name: String
        public let value: String
    }

    /// Lowercased text the search box matches against.
    public var searchText: String {
        ([name, outcome, traceID ?? "", workflowID ?? "", payloadJSON ?? ""]
            + fields.map(\.value)).joined(separator: " ").lowercased()
    }
}

/// Reads the engine's private journal directly, so logs stay readable while the engine is stopped.
public struct DiagnosticsJournal: Sendable {
    public static let fileName = "diagnostics.jsonl"
    static let rotations = 7

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    /// Journal files newest first: the active file, then `.1` through `.7`.
    public var files: [URL] {
        let names = [Self.fileName] + (1...Self.rotations).map { "\(Self.fileName).\($0)" }
        return
            names
            .map { directory.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Bytes the journal holds on disk.
    public func usageBytes() -> Int64 {
        files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// The newest `limit` readable entries, newest first. Unparseable lines are skipped.
    public func entries(limit: Int = 2_000) throws -> [DiagnosticsJournalEntry] {
        var entries: [DiagnosticsJournalEntry] = []
        for url in files {
            guard entries.count < limit else { break }
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw DiagnosticsJournalError.unreadable
            }
            let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            for line in lines.reversed() {
                guard entries.count < limit else { break }
                if let entry = Self.entry(from: Data(line)) {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    /// Every journal file concatenated oldest first, for a support export.
    public func exportText() throws -> String {
        do {
            return try files.reversed().map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        } catch {
            throw DiagnosticsJournalError.unreadable
        }
    }

    static func entry(from line: Data) -> DiagnosticsJournalEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let kind = (object["kind"] as? String).flatMap(DiagnosticsJournalEntry.Kind.init(rawValue:)),
            let atText = object["at"] as? String,
            let at = date(atText)
        else { return nil }
        let name: String
        let outcome: String
        switch kind {
        case .stage:
            name = object["stage"] as? String ?? "other"
            outcome = object["outcome"] as? String ?? "other"
        case .payload:
            name = object["capture_kind"] as? String ?? "other"
            outcome = object["capture_status"] as? String ?? "other"
        case .trading:
            name = object["operation"] as? String ?? "other"
            outcome = object["ledger_event"] as? String ?? object["outcome"] as? String ?? "other"
        }
        let hidden: Set<String> = ["kind", "at", "payload", "created_at_ns"]
        let fields =
            object
            .filter { !hidden.contains($0.key) && !($0.value is NSNull) }
            .map { DiagnosticsJournalEntry.Field(name: $0.key, value: text($0.value)) }
            .sorted { $0.name < $1.name }
        let payloadJSON: String? = object["payload"].flatMap { payload in
            guard !(payload is NSNull),
                let data = try? JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
                )
            else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        let createdAt = (object["created_at_ns"] as? NSNumber)?.stringValue ?? atText
        return DiagnosticsJournalEntry(
            id: "\(createdAt)-\(line.hashValue)",
            kind: kind,
            at: at,
            name: name,
            outcome: outcome,
            traceID: object["trace_id"] as? String,
            workflowID: object["workflow_id"] as? String,
            fields: fields,
            payloadJSON: payloadJSON
        )
    }

    private static func text(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) else {
            return String(describing: value)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func date(_ text: String) -> Date? {
        // The engine writes Python's isoformat: microseconds and a +00:00 offset.
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? fractional.parse(text) { return date }
        return try? Date.ISO8601FormatStyle().parse(text)
    }
}

public enum DiagnosticsJournalError: Error, Equatable, LocalizedError, Sendable {
    case unreadable

    public var errorDescription: String? {
        "The local diagnostics journal could not be read."
    }
}
