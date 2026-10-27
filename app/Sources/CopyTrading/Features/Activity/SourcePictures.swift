import AppKit
import CryptoKit
import DesktopCore
import Foundation

/// Pictures the engine captured with a post, read from the app's own data folder. A file is shown
/// only when its size and SHA-256 match what the engine recorded for it.
struct SourcePictures: Sendable {
    /// `<data folder>/attachments`; nil until the engine's data folder is open.
    let directory: URL?

    @MainActor private static let cache = NSCache<NSString, NSImage>()
    private static let maximumBytes = 1024 * 1024

    @MainActor
    func image(for attachment: SourceAttachmentEvidence) -> NSImage? {
        guard let directory, attachment.status == "available",
            let digest = attachment.sha256, let size = attachment.byteSize,
            digest.count == 64, digest.allSatisfy({ "0123456789abcdef".contains($0) }),
            (1...Self.maximumBytes).contains(size)
        else { return nil }
        if let cached = Self.cache.object(forKey: digest as NSString) { return cached }
        let url = directory.appending(path: String(digest.prefix(2))).appending(path: digest)
        guard let data = Self.read(url, size: size),
            SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == digest,
            let image = NSImage(data: data), image.isValid
        else { return nil }
        Self.cache.setObject(image, forKey: digest as NSString)
        return image
    }

    /// The first picture of a post that can be shown.
    @MainActor
    func firstImage(of event: SourceEventEvidence) -> NSImage? {
        event.attachments.lazy.compactMap { image(for: $0) }.first
    }

    private static func read(_ url: URL, size: Int) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard let data = try? handle.read(upToCount: size + 1), data.count == size else { return nil }
        return data
    }
}
