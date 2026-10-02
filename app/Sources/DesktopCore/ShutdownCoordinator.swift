import Foundation

/// Joins overlapping Stop and Quit requests onto one owned shutdown operation.
public actor ShutdownCoordinator {
    private var shutdownTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init() {}

    /// Returns the in-flight shutdown task so callers and tests can join its exact boundary.
    public func request(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        if let shutdownTask { return shutdownTask }
        generation &+= 1
        let operationGeneration = generation
        let task = Task { [weak self] in
            await operation()
            await self?.finish(operationGeneration)
        }
        shutdownTask = task
        return task
    }

    public func run(_ operation: @escaping @Sendable () async -> Void) async {
        await request(operation).value
    }

    private func finish(_ operationGeneration: UInt64) {
        guard generation == operationGeneration else { return }
        shutdownTask = nil
    }
}
