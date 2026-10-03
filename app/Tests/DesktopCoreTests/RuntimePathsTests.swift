import DesktopCore
import Foundation
import Testing

func runRuntimePathsTests() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "copytrading-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = RuntimePaths(
        applicationSupportDirectory: root.appending(path: "Support", directoryHint: .isDirectory),
        runtimeRoot: root.appending(path: "Runtime", directoryHint: .isDirectory),
        engineSourceRoot: root.appending(path: "Engine", directoryHint: .isDirectory)
    )
    let discovered = try RuntimePaths.discover(environment: [
        "COPYTRADING_STATE_ROOT": root.appending(path: "Probe", directoryHint: .isDirectory).path,
        "COPYTRADING_RUNTIME_ROOT": paths.runtimeRoot.path,
        "COPYTRADING_ENGINE_ROOT": paths.engineSourceRoot.path,
    ])
    try #require(
        paths.databaseURL.lastPathComponent == "application.db",
        "native runtime paths must identify the operational SQLite database")
    try #require(
        discovered.applicationSupportDirectory == root.appending(path: "Probe", directoryHint: .isDirectory),
        "explicit local probe state should stay outside the user's installation directory"
    )
    let firstID = try paths.installationIdentity()
    let secondID = try paths.installationIdentity()
    try #require(firstID == secondID, "installation identity changed across reads")
    try #require(UUID(uuidString: firstID) != nil, "installation identity was not a UUID")
    try #require(
        FileManager.default.fileExists(atPath: paths.applicationSupportDirectory.path),
        "private application support directory was not created"
    )

    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o000)],
        ofItemAtPath: paths.installationIdentityURL.path)
    do {
        try verifyThrows(
            { _ = try paths.installationIdentity() },
            matching: { $0 as? RuntimePathsError == .storageUnavailable },
            "an unreadable existing installation ID must not be replaced"
        )
    } catch {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: paths.installationIdentityURL.path)
        throw error
    }
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o600)],
        ofItemAtPath: paths.installationIdentityURL.path)
    let restoredID = try paths.installationIdentity()
    try #require(restoredID == firstID, "the unreadable ID was replaced")

    let lock = try paths.acquireInstallationLock()
    try verifyThrows(
        { _ = try paths.acquireInstallationLock() },
        matching: { $0 as? RuntimePathsError == .alreadyRunning },
        "a second app owner must be rejected"
    )
    lock.release()
    let replacement = try paths.acquireInstallationLock()
    replacement.release()

    // An engine of another installation, or one outside this support directory, is not ours.
    let engine = paths.runtimeRoot.appending(path: "cpython/python/bin/python3.14")
    try FileManager.default.createDirectory(at: engine.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: URL(filePath: "/bin/sleep"), to: engine)
    let foreignDirectory = root.appending(path: "Other Installation")
    try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
    let foreign = Process()
    foreign.executableURL = engine
    foreign.arguments = ["30"]
    foreign.currentDirectoryURL = foreignDirectory
    try foreign.run()
    defer {
        if foreign.isRunning { foreign.terminate() }
        foreign.waitUntilExit()
    }
    try paths.rejectOrphanedEngine()
    try #require(foreign.isRunning, "another installation's engine must keep running")

    // A live engine may still be draining trading work: it blocks startup instead.
    let staleEngine = Process()
    staleEngine.executableURL = engine
    staleEngine.arguments = ["30"]
    staleEngine.currentDirectoryURL = paths.applicationSupportDirectory
    try staleEngine.run()
    defer {
        if staleEngine.isRunning { staleEngine.terminate() }
        staleEngine.waitUntilExit()
    }
    try verifyThrows(
        { try paths.rejectOrphanedEngine() },
        matching: { $0 as? RuntimePathsError == .staleRuntimeChild },
        "a live engine in this installation must block startup"
    )
    try #require(staleEngine.isRunning, "a live engine must never be killed")
    staleEngine.terminate()
    staleEngine.waitUntilExit()
    try paths.rejectOrphanedEngine()
}
