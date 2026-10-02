import Darwin
import Foundation
import SQLite3

public enum OperationalSchemaError: Error, Equatable, LocalizedError, Sendable {
    case unavailable

    public var errorDescription: String? {
        "The active operational database schema could not be read safely. Start CopyTrading and try again."
    }
}

public enum OperationalSchemaReader {
    /// Read the installed engine database's declared schema in a short read-only SQLite session.
    public static func applicationDatabaseVersion(at databaseURL: URL) throws -> Int {
        var fileInfo = stat()
        guard Darwin.lstat(databaseURL.path, &fileInfo) == 0,
            (fileInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
            fileInfo.st_uid == Darwin.getuid()
        else { throw OperationalSchemaError.unavailable }

        var database: OpaquePointer?
        let openStatus = databaseURL.path.withCString { path in
            sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard openStatus == SQLITE_OK, let database else {
            if let database { sqlite3_close_v2(database) }
            throw OperationalSchemaError.unavailable
        }
        defer { sqlite3_close_v2(database) }
        sqlite3_busy_timeout(database, 500)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
            let statement
        else { throw OperationalSchemaError.unavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw OperationalSchemaError.unavailable
        }
        let version = sqlite3_column_int64(statement, 0)
        guard version > 0, version <= Int64(Int.max) else {
            throw OperationalSchemaError.unavailable
        }
        return Int(version)
    }
}
