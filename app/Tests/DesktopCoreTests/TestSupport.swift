import Foundation
import Testing

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

func verifyThrows(
    _ operation: () throws -> Void,
    matching predicate: (any Error) -> Bool,
    _ message: Comment
) throws {
    let error = try #require(throws: (any Error).self, message) { try operation() }
    try #require(predicate(error), message)
}

func contractFixture(_ name: String, sourceFile: String = #filePath) throws -> Data {
    let packageRoot = URL(fileURLWithPath: sourceFile)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try Data(contentsOf: packageRoot.appending(path: "Resources/Contracts/\(name)"))
}
