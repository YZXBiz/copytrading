import Foundation

public struct RuntimeManifest: Decodable, Sendable {
    public let schemaVersion: Int
    public let artifacts: [RuntimeArtifact]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case artifacts
    }

    public static func load(from url: URL) throws -> RuntimeManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RuntimeManifestError.manifestUnavailable
        }
        let manifest: RuntimeManifest
        do {
            manifest = try JSONDecoder().decode(RuntimeManifest.self, from: data)
        } catch {
            throw RuntimeManifestError.invalidManifest
        }
        guard manifest.schemaVersion == 1,
            !manifest.artifacts.isEmpty,
            Set(manifest.artifacts.map(\.name)).count == manifest.artifacts.count,
            manifest.artifacts.allSatisfy(\.isValid)
        else {
            throw RuntimeManifestError.invalidManifest
        }
        return manifest
    }

    public func artifact(named name: String) throws -> RuntimeArtifact {
        guard let artifact = artifacts.first(where: { $0.name == name }) else {
            throw RuntimeManifestError.artifactMissing(name)
        }
        return artifact
    }

    public func executable(named name: String, under runtimeRoot: URL) throws -> URL {
        let artifact = try artifact(named: name)
        guard Self.isSafePathForValidation(artifact.binaryPath) else {
            throw RuntimeManifestError.unsafeExecutablePath
        }
        let root = runtimeRoot.resolvingSymlinksInPath().standardizedFileURL
        let executable = runtimeRoot.appending(path: artifact.binaryPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard executable.path.hasPrefix(root.path + "/"),
            FileManager.default.isExecutableFile(atPath: executable.path)
        else {
            throw RuntimeManifestError.unsafeExecutablePath
        }
        return executable
    }

    static func isSafePathForValidation(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains(".") && !parts.contains("..") && !parts.contains("")
    }
}

public struct RuntimeArtifact: Decodable, Sendable {
    public let name: String
    public let version: String
    public let platform: String
    public let url: String
    public let filename: String
    public let sha256: String
    public let binaryPath: String
    public let license: String

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case platform
        case url
        case filename
        case sha256
        case binaryPath = "binary_path"
        case license
    }

    fileprivate var isValid: Bool {
        !name.isEmpty
            && !version.isEmpty
            && !platform.isEmpty
            && URL(string: url)?.scheme == "https"
            && !filename.isEmpty
            && sha256.count == 64
            && sha256.allSatisfy(\.isHexDigit)
            && !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && RuntimeManifest.isSafePathForValidation(binaryPath)
    }
}

public enum RuntimeManifestError: Error, Equatable, LocalizedError, Sendable {
    case manifestUnavailable
    case invalidManifest
    case artifactMissing(String)
    case unsafeExecutablePath

    public var errorDescription: String? {
        switch self {
        case .manifestUnavailable:
            "The local runtime manifest could not be read."
        case .invalidManifest:
            "The local runtime manifest is invalid."
        case .artifactMissing:
            "A required local runtime artifact is missing."
        case .unsafeExecutablePath:
            "A runtime executable path is outside the selected runtime folder."
        }
    }
}
