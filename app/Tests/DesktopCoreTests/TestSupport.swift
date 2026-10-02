import Foundation

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

func verify(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw VerificationFailure(description: message) }
}

func verifyThrows(
    _ operation: () throws -> Void,
    matching predicate: (any Error) -> Bool,
    _ message: String
) throws {
    do {
        try operation()
    } catch {
        guard predicate(error) else { throw VerificationFailure(description: message) }
        return
    }
    throw VerificationFailure(description: message)
}

func contractFixture(_ name: String, sourceFile: String = #filePath) throws -> Data {
    let packageRoot = URL(fileURLWithPath: sourceFile)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try Data(contentsOf: packageRoot.appending(path: "Resources/Contracts/\(name)"))
}
