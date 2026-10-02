import Foundation

/// Invalidates status work started before a wake or owned-process restart.
public struct RuntimeGeneration: Equatable, Sendable {
    private var value: UInt64 = 0

    public init() {}

    public var current: UInt64 { value }

    @discardableResult
    public mutating func advance() -> UInt64 {
        value &+= 1
        return value
    }

    public func accepts(_ candidate: UInt64) -> Bool {
        value == candidate
    }
}
