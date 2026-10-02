import DesktopCore
import Foundation
import Security

actor ControlledOwnerAuthenticator: AppOwnerAuthenticator {
    private var continuations: [CheckedContinuation<Void, any Error>] = []
    private var calls = 0
    private var invalidations = 0

    func authenticate(localizedReason: String) async throws {
        calls += 1
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func invalidate() async {
        invalidations += 1
    }

    func callCount() -> Int { calls }

    func invalidationCount() -> Int { invalidations }

    func complete(at index: Int = 0) {
        continuations.remove(at: index).resume()
    }

    func fail(at index: Int = 0, with error: any Error) {
        continuations.remove(at: index).resume(throwing: error)
    }
}

func runAppUnlockSessionTests() async throws {
    try await duplicateWindowAppearanceSharesOneOwnerAuthentication()
    try await failedAndCancelledAuthenticationRemainLocked()
    try await staleAuthenticationCannotUnlockAReopenedWindow()
    try await closingAnOldWindowDoesNotLockTheNewWindow()
    try await openingWithoutTheOwnerCheckStillConfirmsActions()
    try await launchPreferencesDefaultToAskingAndRoundTrip()
}

private func failedAndCancelledAuthenticationRemainLocked() async throws {
    let authenticator = ControlledOwnerAuthenticator()
    let unlock = AppUnlock(authenticator: authenticator)
    let window = UUID()

    let cancelledOpening = Task { try await unlock.openWindow(window) }
    try await waitForAuthenticationCalls(1, from: authenticator)
    await authenticator.fail(at: 0, with: AppUnlockError.authenticationCancelled)
    do {
        try await cancelledOpening.value
        throw VerificationFailure(description: "cancelled owner authentication unexpectedly succeeded")
    } catch AppUnlockError.authenticationCancelled {
        // Expected: cancellation leaves protected content locked.
    }
    let lockedAfterCancellation = await unlock.isUnlocked()
    try verify(!lockedAfterCancellation, "cancellation must leave the owner session locked")

    let failedOpening = Task { try await unlock.openWindow(window) }
    try await waitForAuthenticationCalls(2, from: authenticator)
    await authenticator.fail(at: 0, with: TestAuthenticationFailure.denied)
    do {
        try await failedOpening.value
        throw VerificationFailure(description: "failed owner authentication unexpectedly succeeded")
    } catch AppUnlockError.authenticationUnavailable {
        // Expected: authentication failure is mapped to a fail-closed app error.
    }
    let lockedAfterFailure = await unlock.isUnlocked()
    try verify(!lockedAfterFailure, "failure must leave the owner session locked")

    let retry = Task { try await unlock.openWindow(window) }
    try await waitForAuthenticationCalls(3, from: authenticator)
    await authenticator.complete()
    try await retry.value
    let unlockedAfterRetry = await unlock.isUnlocked()
    try verify(unlockedAfterRetry, "a later successful attempt should be able to unlock the same window")
}

private enum TestAuthenticationFailure: Error {
    case denied
}

private func duplicateWindowAppearanceSharesOneOwnerAuthentication() async throws {
    let authenticator = ControlledOwnerAuthenticator()
    let unlock = AppUnlock(authenticator: authenticator)
    let window = UUID()
    let firstAppearance = Task { try await unlock.openWindow(window) }
    try await waitForAuthenticationCalls(1, from: authenticator)

    let navigationRerender = Task { try await unlock.openWindow(window) }
    await Task.yield()
    let calls = await authenticator.callCount()
    try verify(calls == 1, "duplicate appearance or navigation must reuse the window's owner authentication")

    await authenticator.complete()
    try await firstAppearance.value
    try await navigationRerender.value
    let authorized = await unlock.isUnlocked()
    try verify(authorized, "a successful owner authentication should authorize the current window session")
}

private func staleAuthenticationCannotUnlockAReopenedWindow() async throws {
    let authenticator = ControlledOwnerAuthenticator()
    let unlock = AppUnlock(authenticator: authenticator)
    let firstWindow = UUID()
    let reopenedWindow = UUID()

    let firstOpening = Task { try await unlock.openWindow(firstWindow) }
    try await waitForAuthenticationCalls(1, from: authenticator)
    await unlock.closeWindow(firstWindow)

    let reopened = Task { try await unlock.openWindow(reopenedWindow) }
    try await waitForAuthenticationCalls(2, from: authenticator)

    await authenticator.complete(at: 0)
    do {
        try await firstOpening.value
        throw VerificationFailure(description: "a stale owner authentication callback unexpectedly succeeded")
    } catch is AppUnlockError {
        // Expected: the first window's generation was invalidated by close.
    }
    let authorizedAfterStaleCallback = await unlock.isUnlocked()
    try verify(!authorizedAfterStaleCallback, "a stale callback must not authorize the reopened window")

    await authenticator.complete()
    try await reopened.value
    let authorizedAfterCurrentCallback = await unlock.isUnlocked()
    try verify(authorizedAfterCurrentCallback, "the current window's successful authentication should authorize it")
}

private func closingAnOldWindowDoesNotLockTheNewWindow() async throws {
    let authenticator = ControlledOwnerAuthenticator()
    let unlock = AppUnlock(authenticator: authenticator)
    let firstWindow = UUID()
    let reopenedWindow = UUID()

    let firstOpening = Task { try await unlock.openWindow(firstWindow) }
    try await waitForAuthenticationCalls(1, from: authenticator)
    await authenticator.complete()
    try await firstOpening.value
    await unlock.closeWindow(firstWindow)

    let reopened = Task { try await unlock.openWindow(reopenedWindow) }
    try await waitForAuthenticationCalls(2, from: authenticator)
    await authenticator.complete()
    try await reopened.value

    await unlock.closeWindow(firstWindow)
    let remainsAuthorized = await unlock.isUnlocked()
    try verify(remainsAuthorized, "a delayed close from an old window must not lock the current window")
}

func waitForAuthenticationCalls(
    _ expected: Int,
    from authenticator: ControlledOwnerAuthenticator
) async throws {
    // A wall-clock deadline: a fixed number of yields is not enough on a loaded machine.
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await authenticator.callCount() >= expected { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw VerificationFailure(description: "owner authentication did not reach the injected boundary")
}

private func openingWithoutTheOwnerCheckStillConfirmsActions() async throws {
    let authenticator = ControlledOwnerAuthenticator()
    let unlock = AppUnlock(authenticator: authenticator, ownerCheckRequired: false)
    let window = UUID()
    try await unlock.openWindow(window)
    let unlocked = await unlock.isUnlocked()
    let prompts = await authenticator.callCount()
    try verify(unlocked && prompts == 0, "an owner who turned the check off must open without a prompt")

    let confirming = Task { try await unlock.confirm(localizedReason: "Turn off Touch ID") }
    try await waitForAuthenticationCalls(1, from: authenticator)
    await authenticator.complete()
    try await confirming.value

    await unlock.lock()
    await unlock.setOwnerCheckRequired(true)
    let reopening = Task { try await unlock.openWindow(window) }
    try await waitForAuthenticationCalls(2, from: authenticator)
    let stillLocked = await unlock.isUnlocked()
    try verify(!stillLocked, "turning the check back on must ask again after a lock")
    await authenticator.complete()
    try await reopening.value
}

private func launchPreferencesDefaultToAskingAndRoundTrip() async throws {
    let store = LaunchPreferencesStore(
        stateRoot: URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString),
        service: "com.copytrading.test.launch.\(UUID().uuidString)"
    )
    defer { store.delete() }
    try verify(store.load() == LaunchPreferences(), "an absent preference must ask for the owner")
    let chosen = LaunchPreferences(asksForOwner: false, startsCopying: true)
    try store.save(chosen)
    try verify(store.load() == chosen, "launch preferences did not round-trip through the Keychain")
}
