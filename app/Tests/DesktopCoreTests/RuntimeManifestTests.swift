import DesktopCore
import Foundation

func runRuntimeManifestTests() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let manifestURL = packageRoot.appending(path: "Resources/Runtime/artifacts.json")
    let manifest = try RuntimeManifest.load(from: manifestURL)
    let python = try manifest.artifact(named: "cpython")

    try verify(manifest.artifacts.map(\.name) == ["cpython"], "the runtime must bundle Python and nothing else")
    try verify(python.version.hasPrefix("3.14.7"), "Python runtime pin changed")
    try verify(python.sha256.count == 64, "Python runtime digest is not a SHA-256")

    let temp = FileManager.default.temporaryDirectory
        .appending(path: "runtime-manifest-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: temp) }
    try FileManager.default.createDirectory(at: temp.appending(path: "cpython/python/bin"), withIntermediateDirectories: true)
    let executable = temp.appending(path: "cpython/python/bin/python3.14")
    try Data("native placeholder".utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o700)],
        ofItemAtPath: executable.path
    )
    let resolved = try manifest.executable(named: "cpython", under: temp)
    try verify(resolved == executable, "manifest binary path did not resolve under runtime root")

    try FileManager.default.removeItem(at: executable)
    try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: URL(fileURLWithPath: "/bin/echo"))
    try verifyThrows(
        { _ = try manifest.executable(named: "cpython", under: temp) },
        matching: { $0 as? RuntimeManifestError == .unsafeExecutablePath },
        "runtime executable symlink must not escape its root"
    )
}
