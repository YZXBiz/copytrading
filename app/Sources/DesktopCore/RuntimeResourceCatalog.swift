import Foundation

public enum RuntimeResourceCatalog {
    public enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case missingResource
        case invalidResource

        public var errorDescription: String? {
            switch self {
            case .missingResource:
                "A required local runtime configuration is missing."
            case .invalidResource:
                "The local runtime configuration is invalid."
            }
        }
    }

    public static func url(forResource name: String, extension fileExtension: String) throws -> URL {
        if let packaged = Bundle.main.resourceURL?
            .appending(path: "Runtime", directoryHint: .isDirectory)
            .appending(path: "\(name).\(fileExtension)"),
            FileManager.default.fileExists(atPath: packaged.path)
        {
            return packaged
        }
        #if DEBUG
            let url = Bundle.module.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: "Runtime"
            )
            guard let url else { throw Error.missingResource }
            return url
        #else
            throw Error.missingResource
        #endif
    }

    public static func runtimeManifest() throws -> RuntimeManifest {
        try RuntimeManifest.load(from: url(forResource: "artifacts", extension: "json"))
    }
}
