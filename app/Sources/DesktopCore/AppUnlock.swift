import Foundation
import LocalAuthentication

public protocol AppOwnerAuthenticator: Sendable {
    func authenticate(localizedReason: String) async throws
    func invalidate() async
}

private actor SystemOwnerAuthenticator: AppOwnerAuthenticator {
    private var context: LAContext?
    private var generation: UInt64 = 0

    func authenticate(localizedReason: String) async throws {
        let requestGeneration = generation
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw AppUnlockError.authenticationUnavailable
        }
        self.context = context

        do {
            guard
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: localizedReason
                )
            else {
                throw AppUnlockError.authenticationCancelled
            }
            guard generation == requestGeneration else {
                throw AppUnlockError.authenticationCancelled
            }
            self.context = nil
        } catch let error as LAError where error.code == .userCancel {
            context.invalidate()
            throw AppUnlockError.authenticationCancelled
        } catch let error as AppUnlockError {
            context.invalidate()
            throw error
        } catch {
            context.invalidate()
            throw AppUnlockError.authenticationUnavailable
        }
    }

    func invalidate() async {
        generation &+= 1
        context?.invalidate()
        context = nil
    }
}

/// Shares one owner-authentication result across the app's protected native controls.
public actor AppUnlock {
    private struct AuthenticationAttempt {
        let id: UUID
        let task: Task<Void, any Error>
    }

    private let authenticator: any AppOwnerAuthenticator
    private var authenticationAttempt: AuthenticationAttempt?
    private var activeWindowSession: UUID?
    private var generation: UInt64 = 0
    private var authorized = false
    /// Off when the owner chose not to be asked on open; explicit confirmations still ask.
    private var ownerCheckRequired: Bool

    public init(
        authenticator: (any AppOwnerAuthenticator)? = nil,
        ownerCheckRequired: Bool = true
    ) {
        self.authenticator = authenticator ?? SystemOwnerAuthenticator()
        self.ownerCheckRequired = ownerCheckRequired
    }

    public func setOwnerCheckRequired(_ required: Bool) {
        ownerCheckRequired = required
    }

    /// Begin or reuse the authorization session for one actual window instance.
    public func openWindow(
        _ sessionID: UUID,
        localizedReason: String = "Unlock CopyTrading"
    ) async throws {
        var openingGeneration = generation
        if activeWindowSession != sessionID {
            let priorTask = authenticationAttempt?.task
            authenticationAttempt = nil
            generation &+= 1
            openingGeneration = generation
            authorized = false
            activeWindowSession = sessionID
            priorTask?.cancel()
            if priorTask != nil { await authenticator.invalidate() }
        }
        try await authenticate(
            localizedReason: localizedReason,
            expectedWindowSession: sessionID,
            expectedGeneration: openingGeneration
        )
    }

    private func authenticate(
        localizedReason: String,
        expectedWindowSession: UUID?,
        expectedGeneration: UInt64
    ) async throws {
        guard generation == expectedGeneration,
            activeWindowSession == expectedWindowSession
        else {
            throw AppUnlockError.authenticationCancelled
        }
        if authorized { return }
        if !ownerCheckRequired {
            authorized = true
            return
        }
        let attempt: AuthenticationAttempt
        if let authenticationAttempt {
            attempt = authenticationAttempt
        } else {
            let authenticator = self.authenticator
            attempt = AuthenticationAttempt(
                id: UUID(),
                task: Task { try await authenticator.authenticate(localizedReason: localizedReason) }
            )
            authenticationAttempt = attempt
        }

        do {
            try await attempt.task.value
        } catch {
            if generation == expectedGeneration, authenticationAttempt?.id == attempt.id {
                authenticationAttempt = nil
                authorized = false
            }
            if let unlockError = error as? AppUnlockError { throw unlockError }
            throw AppUnlockError.authenticationUnavailable
        }
        guard generation == expectedGeneration,
            activeWindowSession == expectedWindowSession
        else {
            throw AppUnlockError.authenticationCancelled
        }
        authorized = true
        if authenticationAttempt?.id == attempt.id {
            authenticationAttempt = nil
        }
    }

    /// Lock the current session but leave its window identity available for an explicit retry.
    public func lock() async {
        await clearAuthorization(clearWindow: false)
    }

    /// A stale close notification cannot clear a newer window's authorization session.
    public func closeWindow(_ sessionID: UUID) async {
        guard activeWindowSession == sessionID else { return }
        activeWindowSession = nil
        await clearAuthorization(clearWindow: true)
    }

    public func isUnlocked() -> Bool {
        authorized
    }

    /// Ask the owner to confirm one action, even inside an unlocked session.
    ///
    /// Each confirmation is a fresh authentication. It requires an unlocked app, and locking
    /// or closing the window while the prompt is open cancels it.
    public func confirm(localizedReason: String) async throws {
        guard authorized else { throw AppUnlockError.authenticationCancelled }
        let expectedGeneration = generation
        do {
            try await authenticator.authenticate(localizedReason: localizedReason)
        } catch let error as AppUnlockError {
            throw error
        } catch {
            throw AppUnlockError.authenticationUnavailable
        }
        guard authorized, generation == expectedGeneration else {
            throw AppUnlockError.authenticationCancelled
        }
    }

    private func clearAuthorization(clearWindow: Bool) async {
        generation &+= 1
        authorized = false
        let attempt = authenticationAttempt
        authenticationAttempt = nil
        attempt?.task.cancel()
        if clearWindow { activeWindowSession = nil }
        await authenticator.invalidate()
    }
}

public enum AppUnlockError: Error, Equatable, LocalizedError, Sendable {
    case authenticationCancelled
    case authenticationUnavailable

    public var errorDescription: String? {
        switch self {
        case .authenticationCancelled:
            "CopyTrading remains locked."
        case .authenticationUnavailable:
            "Local authentication is unavailable."
        }
    }
}
