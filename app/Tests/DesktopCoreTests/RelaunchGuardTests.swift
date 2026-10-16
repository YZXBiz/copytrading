import DesktopCore
import Foundation
import Testing

/// A stand-in app bundle whose executable and Sparkle helper are copies of `sleep`, so the guard
/// sees them by path the way it sees the real ones, and an opener that writes down what it opened.
private struct FakeApp {
    let root: URL
    let bundle: URL
    let executable: URL
    let installer: URL
    let opener: URL
    let opened: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("relaunch-guard-\(UUID().uuidString)")
        bundle = root.appendingPathComponent("Fake App.app")
        executable = bundle.appendingPathComponent("Contents/MacOS/Fake App")
        installer = bundle.appendingPathComponent("Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate")
        opener = root.appendingPathComponent("opener")
        opened = root.appendingPathComponent("opened")
        for copy in [executable, installer] {
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: copy)
        }
        try "#!/bin/sh\nprintf '%s' \"$1\" > '\(opened.path)'\n".write(to: opener, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path)
    }

    func run(_ executable: URL, seconds: Int) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = [String(seconds)]
        try process.run()
        return process
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// Waits for the guard to finish, as its parent must, and reports whether it did in time.
private func finished(_ pid: pid_t, within seconds: Double) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    var status: Int32 = 0
    while Date() < deadline {
        if waitpid(pid, &status, WNOHANG) == pid { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return false
}

@Test func anAppTheInstallerNeverReopenedIsOpenedAgainAndTheStuckInstallerStopped() async throws {
    let app = try FakeApp()
    defer { app.remove() }
    let quitting = try app.run(URL(fileURLWithPath: "/bin/sleep"), seconds: 1)
    let stuckInstaller = try app.run(app.installer, seconds: 300)
    defer { stuckInstaller.terminate() }

    let guardPID = try RelaunchGuard.start(
        appPID: quitting.processIdentifier, executable: app.executable, bundle: app.bundle, patience: 2,
        opener: app.opener)

    #expect(await finished(guardPID, within: 15))
    #expect(try String(contentsOf: app.opened, encoding: .utf8) == app.bundle.path)
    stuckInstaller.waitUntilExit()
    #expect(stuckInstaller.terminationReason == .uncaughtSignal, "the hung installer is stopped first")
}

@Test func anAppTheUpdateReopenedIsLeftAlone() async throws {
    let app = try FakeApp()
    defer { app.remove() }
    let quitting = try app.run(URL(fileURLWithPath: "/bin/sleep"), seconds: 1)
    let reopened = try app.run(app.executable, seconds: 30)
    defer { reopened.terminate() }

    let guardPID = try RelaunchGuard.start(
        appPID: quitting.processIdentifier, executable: app.executable, bundle: app.bundle, patience: 5,
        opener: app.opener)

    #expect(await finished(guardPID, within: 10))
    #expect(!FileManager.default.fileExists(atPath: app.opened.path), "nothing opens a second copy")
    #expect(reopened.isRunning)
}

@Test func theGuardOutlivesItsAppAndHoldsNoneOfItsFiles() throws {
    let app = try FakeApp()
    defer { app.remove() }
    let lock = app.root.appendingPathComponent("lock")
    FileManager.default.createFile(atPath: lock.path, contents: nil)
    let held = open(lock.path, O_RDONLY)
    #expect(flock(held, LOCK_EX | LOCK_NB) == 0)

    let guardPID = try RelaunchGuard.start(
        appPID: getpid(), executable: app.executable, bundle: app.bundle, opener: app.opener)
    defer {
        kill(guardPID, SIGKILL)
        waitpid(guardPID, nil, 0)
    }
    close(held)

    #expect(getsid(guardPID) == guardPID, "a session of its own, so the app's exit doesn't end it")
    let next = open(lock.path, O_RDONLY)
    defer { close(next) }
    #expect(flock(next, LOCK_EX | LOCK_NB) == 0, "the guard holds no copy of the app's lock")
}

@Test func theFoldersMacOSGuardsAreKnownAndOthersAreNot() {
    let home = URL(fileURLWithPath: "/Users/owner")
    func folder(_ path: String) -> ProtectedFolder? {
        ProtectedFolder.containing(URL(fileURLWithPath: path), home: home)
    }
    #expect(folder("/Users/owner/Desktop/CopyTrading.app") == .desktop)
    #expect(folder("/Users/owner/Documents/Apps/CopyTrading.app") == .documents)
    #expect(folder("/Users/owner/Downloads/CopyTrading.app") == .downloads)
    #expect(folder("/Users/owner/Library/Mobile Documents/com~apple~CloudDocs/CopyTrading.app") == .iCloudDrive)
    #expect(folder("/Users/owner/Library/CloudStorage/Dropbox/CopyTrading.app") == .cloudStorage)
    #expect(folder("/Applications/CopyTrading.app") == nil)
    #expect(folder("/Users/owner/Applications/CopyTrading.app") == nil)
    #expect(folder("/Users/owner/DesktopApps/CopyTrading.app") == nil)
}
