import DesktopCore
import Foundation

extension AppModel {
    /// Checks one connection with what is typed for it, filling any blank key from the Keychain,
    /// and remembers the answer for as long as those fields stay as they are. Returns nil when
    /// there is nothing to check yet or the engine cannot check right now.
    @discardableResult
    func checkConnection(_ subject: ConnectionCheckSubject) async -> TradingCapabilityCheck? {
        guard isTradingUnlocked, let checker = connectionChecker,
            let connection = connectionCheck(for: subject)
        else { return nil }
        let fingerprint = connectionFingerprint(subject)
        connectionChecks[subject] = ConnectionCheckResult(fingerprint: fingerprint, check: nil)
        do {
            let check = try await checker.checkConnection(connection)
            connectionChecks[subject] = ConnectionCheckResult(fingerprint: fingerprint, check: check)
            return check
        } catch {
            connectionChecks[subject] = nil
            return nil
        }
    }

    /// The connection's latest check, unless something it checked has been edited since.
    func connectionCheckResult(_ subject: ConnectionCheckSubject) -> ConnectionCheckResult? {
        guard let result = connectionChecks[subject], result.fingerprint == connectionFingerprint(subject) else {
            return nil
        }
        return result
    }

    /// A full check answers for every connection at once, so each row shows its own answer too.
    func recordConnectionChecks(_ checks: [TradingCapabilityCheck]) {
        for check in checks {
            let subject: ConnectionCheckSubject? =
                switch check.name {
                case .source: .discord
                case .model: .interpreter
                case .notification: check.state == .notConfigured ? nil : .alerts
                case .broker: check.subject.map(ConnectionCheckSubject.account)
                default: nil
                }
            guard let subject else { continue }
            connectionChecks[subject] = ConnectionCheckResult(fingerprint: connectionFingerprint(subject), check: check)
        }
    }

    /// The service as typed, with any blank key filled from the saved setup; nil until it can be
    /// checked at all.
    private func connectionCheck(for subject: ConnectionCheckSubject) -> TradingConnectionCheck? {
        let draft = setupDraft
        let saved = savedSetup()
        switch subject {
        case .discord:
            let channels = draft.sourceChannelIDs
            let token = draft.discordToken.isEmpty ? saved?.secrets.discordToken ?? "" : draft.discordToken
            guard !channels.isEmpty, !token.isEmpty else { return nil }
            return .source(
                TradingSourceConfiguration(channelIDs: channels, authorIDs: ConnectionsDraft.split(draft.authors)),
                token: token)
        case .interpreter:
            let provider = draft.providerConfiguration
            let key = Self.providerKey(entered: draft.providerAPIKey, for: provider.name, saved: saved)
            guard !provider.model.isEmpty, draft.providerConfiguration.baseURLProblem == nil,
                !key.isEmpty || !provider.name.requiresAPIKey
            else { return nil }
            return .model(provider, apiKey: key)
        case .alerts:
            guard draft.notificationsEnabled else { return nil }
            let sameService = saved?.configuration.notification?.service == draft.notificationService
            let token =
                draft.notificationToken.isEmpty
                ? (sameService ? saved?.secrets.notificationToken ?? "" : "") : draft.notificationToken
            guard !token.isEmpty else { return nil }
            return .notification(
                TradingNotificationConfiguration(
                    service: draft.notificationService, chatID: draft.notificationChatID.trimmed),
                token: token)
        case .account(let name):
            guard let account = draft.accounts.first(where: { $0.name.trimmed == name }), !name.isEmpty else {
                return nil
            }
            let savedKeys = saved?.secrets.brokers.first { $0.accountID == name }
            let key = account.key.isEmpty ? savedKeys?.key ?? "" : account.key
            let secret = account.secret.isEmpty ? savedKeys?.secret ?? "" : account.secret
            guard !key.isEmpty, !secret.isEmpty else { return nil }
            return .broker(
                TradingAccountConfiguration(id: name, environment: account.environment, policy: account.policy),
                credentials: TradingBrokerCredentials(accountID: name, key: key, secret: secret))
        }
    }

    /// A digest of every field the connection's check covers. It never leaves memory.
    private func connectionFingerprint(_ subject: ConnectionCheckSubject) -> Int {
        let draft = setupDraft
        var hasher = Hasher()
        switch subject {
        case .discord:
            hasher.combine(draft.sourceChannelIDs)
            hasher.combine(ConnectionsDraft.split(draft.authors))
            hasher.combine(draft.discordToken)
        case .interpreter:
            hasher.combine(draft.provider)
            hasher.combine(draft.modelName.trimmed)
            hasher.combine(draft.providerBaseURL.trimmed)
            hasher.combine(draft.providerAPIKey)
        case .alerts:
            hasher.combine(draft.notificationsEnabled)
            hasher.combine(draft.notificationService)
            hasher.combine(draft.notificationChatID.trimmed)
            hasher.combine(draft.notificationToken)
        case .account(let name):
            let account = draft.accounts.first { $0.name.trimmed == name }
            hasher.combine(name)
            hasher.combine(account?.environment)
            hasher.combine(account?.key)
            hasher.combine(account?.secret)
        }
        return hasher.finalize()
    }
}
