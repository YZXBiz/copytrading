import Darwin
import Foundation

public final class InstallationLock: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32?
    public let url: URL

    init(descriptor: Int32, url: URL) {
        self.descriptor = descriptor
        self.url = url.standardizedFileURL
    }

    public var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return descriptor != nil
    }

    public func release() {
        lock.lock()
        defer { lock.unlock() }
        guard let descriptor else { return }
        self.descriptor = nil
        Darwin.close(descriptor)
    }

    deinit {
        release()
    }
}
