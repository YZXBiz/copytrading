import AppKit
import DesktopCore
import Foundation
import Testing

@MainActor
func runAppWindowLifecycleTests() async throws {
    try await reopenedNativeWindowAuthenticatesItsOwnSession()
    try await staleRetryFailureCannotChangeReopenedWindowUI()
    try verifyStopReportMessageExplainsUnconfirmedDrain()
}

@MainActor
private func reopenedNativeWindowAuthenticatesItsOwnSession() async throws {
    let authenticator = WindowOwnerAuthenticator()
    let unlock = AppUnlock(authenticator: authenticator)
    let model = AppModel(appUnlock: unlock)
    var openedSessions: [UUID] = []
    var closedSessions: [UUID] = []
    let monitor = WindowSessionMonitor.Coordinator(
        onOpen: { sessionID in
            openedSessions.append(sessionID)
            _ = model.windowDidOpen(sessionID)
        },
        onClose: { sessionID in
            closedSessions.append(sessionID)
            _ = model.windowDidClose(sessionID)
        }
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 80),
        styleMask: [.titled],
        backing: .buffered,
        defer: true
    )

    monitor.attach(to: window)
    try await authenticator.waitForCalls(1)
    NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
    monitor.attach(to: window)
    try await authenticator.waitForCalls(2)

    try #require(openedSessions.count == 2, "the native window notification bridge must issue a fresh opening token")
    try #require(openedSessions[0] != openedSessions[1], "reopening the same native window must get a new session token")
    try #require(closedSessions == [openedSessions[0]], "willClose must call AppModel.windowDidClose for the closing token")

    await authenticator.fail(at: 0, with: AppUnlockError.authenticationCancelled)
    try #require(!model.isTradingUnlocked, "the closed window's cancelled prompt must not unlock anything")
    await authenticator.complete(at: 0)
    try await waitUntil("reopened window authorization") { model.isTradingUnlocked }
    let authorized = await unlock.isUnlocked()
    try #require(authorized, "the reopened window's owner session must be authorized")
}

@MainActor
private func staleRetryFailureCannotChangeReopenedWindowUI() async throws {
    let authenticator = WindowOwnerAuthenticator()
    let unlock = AppUnlock(authenticator: authenticator)
    let model = AppModel(appUnlock: unlock)
    model.windowDidOpen(UUID())
    try await authenticator.waitForCalls(1)
    await authenticator.fail(at: 0, with: AppUnlockError.authenticationCancelled)
    try await waitUntil("first authentication cancellation") { !model.isUnlockingTrading }

    let staleRetry = Task { await model.unlockTrading() }
    try await authenticator.waitForCalls(2)
    model.windowDidOpen(UUID())
    try await authenticator.waitForCalls(3)

    await authenticator.fail(at: 0, with: AppUnlockError.authenticationUnavailable)
    await staleRetry.value
    try #require(model.isUnlockingTrading, "a stale retry must not clear the reopened window's in-flight state")
    try #require(!model.isTradingUnlocked, "a stale retry must not change the reopened window authorization state")
    try #require(model.accessMessage == nil, "a stale retry must not publish an error into the reopened window")

    await authenticator.complete(at: 0)
    try await waitUntil("reopened window authorization after stale retry") { model.isTradingUnlocked }
}

@MainActor
private func verifyStopReportMessageExplainsUnconfirmedDrain() throws {
    let report = ProcessSupervisorStopReport(
        engineDrainAcknowledgement: .unconfirmed,
        forciblyStoppedChildren: [.engine]
    )
    let message = AppModel.stopMessage(for: report)
    try #require(message.contains("did not confirm its graceful drain"), "Stop must identify an unconfirmed engine drain")
    try #require(message.contains("Forced termination was required for: engine"), "Stop must disclose a forced owned-process stop")
    try #require(message.contains("Broker-accepted orders may remain open"), "Stop must explain broker orders can remain outstanding")
}

private actor WindowOwnerAuthenticator: AppOwnerAuthenticator {
    private var continuations: [CheckedContinuation<Void, any Error>] = []
    private var calls = 0

    func authenticate(localizedReason: String) async throws {
        calls += 1
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func invalidate() async {}

    func callCount() -> Int { calls }

    func waitForCalls(_ expected: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if calls >= expected { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw WindowLifecycleTestFailure(description: "owner-auth prompt did not reach the injected boundary")
    }

    func waitForCalls(_ expected: Int, within timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if calls >= expected { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return calls >= expected
    }

    func complete(at index: Int) {
        continuations.remove(at: index).resume()
    }

    func fail(at index: Int, with error: any Error) {
        continuations.remove(at: index).resume(throwing: error)
    }
}

@MainActor
private func waitUntil(
    _ description: String,
    condition: @MainActor () -> Bool
) async throws {
    for _ in 0..<1_000 {
        if condition() { return }
        await Task.yield()
    }
    throw WindowLifecycleTestFailure(description: "timed out waiting for \(description)")
}

private struct WindowLifecycleTestFailure: Error, LocalizedError {
    let description: String
    var errorDescription: String? { description }
}
