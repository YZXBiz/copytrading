import Foundation

/// What an import filled from the file the owner chose, shown until they decide what happens to
/// the file. It holds no value from the file.
struct SetupImportResult: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
    let filled: [String]
    let missing: [String]
}
