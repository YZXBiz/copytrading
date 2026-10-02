import DesktopCore
import Foundation

private actor ShutdownBoundary {
    private var invocations = 0
    private var hasEntered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func shutdown() async {
        invocations += 1
        guard invocations == 1 else { return }
        hasEntered = true
        entryWaiter?.resume()
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func invocationCount() -> Int { invocations }
}

func runShutdownCoordinatorTests() async throws {
    let coordinator = ShutdownCoordinator()
    let boundary = ShutdownBoundary()
    let stop = await coordinator.request { await boundary.shutdown() }
    await boundary.waitUntilEntered()

    let quit = await coordinator.request { await boundary.shutdown() }
    await boundary.release()
    await stop.value
    await quit.value

    let joinedInvocationCount = await boundary.invocationCount()
    try verify(joinedInvocationCount == 1, "Quit must join an in-flight Stop drain instead of duplicating shutdown")

    let later = await coordinator.request { await boundary.shutdown() }
    await later.value
    let laterInvocationCount = await boundary.invocationCount()
    try verify(laterInvocationCount == 2, "a later runtime lifecycle must be allowed to stop independently")
}
