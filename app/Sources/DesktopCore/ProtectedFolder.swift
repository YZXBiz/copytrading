import Foundation

/// A folder macOS guards: only an app the owner allowed may change what is in it. Sparkle replaces
/// the app from a helper of its own after the app has quit, and macOS stops that helper to ask
/// the owner first. Nobody is there to answer, so nothing installs and the app stays quit; on
/// October 14 that left copying off all night. An app in one of these folders can't update itself.
public enum ProtectedFolder: String, CaseIterable, Sendable {
    case desktop
    case documents
    case downloads
    case iCloudDrive
    /// Dropbox, Google Drive, OneDrive and other synced folders.
    case cloudStorage

    /// Where each one sits under the home folder.
    private var path: String {
        switch self {
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .iCloudDrive: "Library/Mobile Documents"
        case .cloudStorage: "Library/CloudStorage"
        }
    }

    /// The guarded folder `bundle` sits in, or nil when the updater may replace it.
    public static func containing(
        _ bundle: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ProtectedFolder? {
        let bundlePath = bundle.resolvingSymlinksInPath().standardizedFileURL.path
        let homePath = home.resolvingSymlinksInPath().standardizedFileURL.path
        return allCases.first { bundlePath.hasPrefix("\(homePath)/\($0.path)/") }
    }
}
