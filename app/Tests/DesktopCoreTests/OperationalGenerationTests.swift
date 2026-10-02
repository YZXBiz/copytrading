import DesktopCore
import Foundation

func runOperationalGenerationTests() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "copytrading-generations-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let ownerPaths = RuntimePaths(
        applicationSupportDirectory: root,
        runtimeRoot: root.appending(path: "Runtime", directoryHint: .isDirectory),
        engineSourceRoot: root.appending(path: "Engine", directoryHint: .isDirectory)
    )
    let lock = try ownerPaths.acquireInstallationLock()
    let first = try ownerPaths.resolveActiveGeneration(whileHolding: lock)
    let firstID = try unwrap(first.activeGenerationID, "the first owner did not select a generation")
    try verify(
        first.applicationSupportDirectory.path == root.appending(path: "generations/\(firstID)").path,
        "operational data must live under its immutable generation directory")
    try verify(
        first.lockURL.path == root.appending(path: ".app.lock").path,
        "owner lock must remain outside swappable generations")
    try verify(
        first.installationIdentityURL.path == root.appending(path: "installation-id").path,
        "installation identity must remain stable outside swappable generations")
    try verify(
        first.logsDirectory.path == root.appending(path: "logs").path,
        "logs must remain outside swappable operational generations")

    let candidateID = UUID().uuidString.lowercased()
    let candidate = root.appending(path: "generations/\(candidateID)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: candidate.path)
    try Data("manual-disabled".utf8).write(to: candidate.appending(path: "restore-gate"))
    let previous = try ownerPaths.switchActiveGeneration(
        to: candidateID,
        expectedCurrentGeneration: firstID,
        whileHolding: lock
    )
    try verify(previous == firstID, "generation switch did not return the rollback target")
    let selected = try ownerPaths.resolveActiveGeneration(whileHolding: lock)
    try verify(
        selected.activeGenerationID == candidateID,
        "active generation pointer did not select the staged candidate")
    try verify(
        FileManager.default.fileExists(atPath: candidate.appending(path: "restore-gate").path),
        "generation switch removed the candidate state")

    try verifyThrows(
        {
            _ = try ownerPaths.switchActiveGeneration(
                to: firstID,
                expectedCurrentGeneration: firstID,
                whileHolding: lock
            )
        },
        matching: { $0 as? RuntimePathsError == .activeGenerationChanged },
        "concurrent generation changes must preserve the currently selected pointer"
    )
    let unchanged = try ownerPaths.resolveActiveGeneration(whileHolding: lock)
    try verify(
        unchanged.activeGenerationID == candidateID,
        "a rejected generation switch modified the active pointer")

    try verifyThrows(
        {
            _ = try ownerPaths.switchActiveGeneration(
                to: "../outside",
                expectedCurrentGeneration: candidateID,
                whileHolding: lock
            )
        },
        matching: { $0 as? RuntimePathsError == .invalidGeneration },
        "generation paths must reject traversal values"
    )

    lock.release()
    try verifyThrows(
        { _ = try ownerPaths.resolveActiveGeneration(whileHolding: lock) },
        matching: { $0 as? RuntimePathsError == .installationLockRequired },
        "a released owner lock must not authorize resolving or switching data"
    )

    let externalLockTarget = root.deletingLastPathComponent()
        .appending(path: "external-owner-lock-\(UUID().uuidString)")
    try Data("outside".utf8).write(to: externalLockTarget)
    try FileManager.default.removeItem(at: ownerPaths.lockURL)
    try FileManager.default.createSymbolicLink(
        at: ownerPaths.lockURL,
        withDestinationURL: externalLockTarget
    )
    try verifyThrows(
        { _ = try ownerPaths.acquireInstallationLock() },
        matching: { $0 as? RuntimePathsError == .storageUnavailable },
        "the stable owner lock must reject a symbolic-link replacement"
    )
    let externalLockContents = try Data(contentsOf: externalLockTarget)
    try verify(
        externalLockContents == Data("outside".utf8),
        "the stable owner lock must not open or mutate a symbolic-link target")
}

private func unwrap<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw VerificationFailure(description: message) }
    return value
}
