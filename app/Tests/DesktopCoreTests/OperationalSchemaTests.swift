import DesktopCore
import Foundation
import SQLite3
import Testing

func runOperationalSchemaTests() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "copytrading-schema-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let databaseURL = root.appending(path: "application.db")
    var database: OpaquePointer?
    let openStatus = databaseURL.path.withCString { sqlite3_open_v2($0, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) }
    try #require(openStatus == SQLITE_OK, "test database must open")
    guard let database else { throw VerificationFailure(description: "test database handle is missing") }
    defer { sqlite3_close_v2(database) }
    try #require(
        sqlite3_exec(database, "PRAGMA user_version = 17", nil, nil, nil) == SQLITE_OK,
        "test database schema must be set")
    let installedVersion = try OperationalSchemaReader.applicationDatabaseVersion(at: databaseURL)
    try #require(installedVersion == 17, "update compatibility must use the installed SQLite user_version")

    try verifyThrows(
        { _ = try OperationalSchemaReader.applicationDatabaseVersion(at: root.appending(path: "missing.db")) },
        matching: { $0 as? OperationalSchemaError == .unavailable },
        "missing operational schema must fail closed"
    )

    let corruptURL = root.appending(path: "corrupt.db")
    try Data("not a SQLite database".utf8).write(to: corruptURL)
    try verifyThrows(
        { _ = try OperationalSchemaReader.applicationDatabaseVersion(at: corruptURL) },
        matching: { $0 as? OperationalSchemaError == .unavailable },
        "corrupt operational schema must fail closed"
    )
}
