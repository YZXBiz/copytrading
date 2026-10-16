import DesktopCore

@MainActor
extension ProtectedFolder {
    /// The folder's name as Finder shows it.
    public var name: String {
        switch self {
        case .desktop: L10n.string("Desktop")
        case .documents: L10n.string("Documents")
        case .downloads: L10n.string("Downloads")
        case .iCloudDrive: L10n.string("iCloud Drive")
        case .cloudStorage: L10n.string("cloud storage")
        }
    }

    /// Why an update can't install from here, said when the owner checks for one.
    public var updateRefusal: String {
        L10n.string(
            "CopyTrading is in your %@ folder, where macOS won't let the updater replace it: the update would quit CopyTrading without installing. Move CopyTrading to Applications, open it from there, and check again.",
            name)
    }
}
