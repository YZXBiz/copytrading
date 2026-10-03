import DesktopCore
import Foundation
import Testing

func runTradingConfigurationPersistenceTests() throws {
    try failedFileCommitKeepsPriorPair()
    try activeStateRejectsBeforeWrites()
    try unsupportedVersionRejectsBeforeWrites()
    try olderVersionIsDiscardedNotMigrated()
    try successfulReplacementChangesReference()
    try pendingActivationSurvivesStoreReopenAndFinalizesOnCommit()
    try pendingActivationSurvivesStoreReopenAndRollsBackOnlyOnRequest()
}

private func olderVersionIsDiscardedNotMigrated() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let store = TradingConfigurationStore(url: file, secrets: secrets)
    let discardedMissing = try store.discardOlderVersion()
    try #require(!discardedMissing, "a missing setup file was reported as discarded")
    let current = try tradingConfiguration(model: "current")
    try store.save(
        configuration: current, revision: fakeEngineRevision(current), secrets: tradingCredentials(token: "current"), when: .paused)
    let discardedCurrent = try store.discardOlderVersion()
    let currentLoaded = try store.load()
    try #require(!discardedCurrent, "a current setup was discarded")
    try #require(currentLoaded != nil, "a current setup stopped loading")

    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
    var older = saved
    var configuration = saved["configuration"] as? [String: Any] ?? [:]
    configuration["version"] = TradingConfiguration.currentVersion - 1
    older["configuration"] = configuration
    try JSONSerialization.data(withJSONObject: older).write(to: file)
    guard let secretRevision = UUID(uuidString: saved["secretRevision"] as? String ?? "") else {
        throw VerificationFailure(description: "the saved setup had no secret revision")
    }
    let keptSecrets = try secrets.load(revision: secretRevision)
    try #require(keptSecrets != nil, "the test lost its saved secrets")

    let discardedOlder = try store.discardOlderVersion()
    let leftoverSecrets = try secrets.load(revision: secretRevision)
    let loadedAfter = try store.load()
    try #require(discardedOlder, "an older-version setup was kept")
    try #require(!FileManager.default.fileExists(atPath: file.path), "the older setup file was left behind")
    try #require(leftoverSecrets == nil, "the older setup's Keychain item was left behind")
    try #require(loadedAfter == nil, "the app did not start clean after discarding an older setup")
}

private func unsupportedVersionRejectsBeforeWrites() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let writer = ControlledConfigurationWriter()
    let store = TradingConfigurationStore(url: file, secrets: secrets, writer: writer)
    let original = try tradingConfiguration(model: "original")
    let credentials = tradingCredentials(token: "original-secret")
    try store.save(configuration: original, revision: fakeEngineRevision(original), secrets: credentials, when: .paused)
    let originalJSON = try Data(contentsOf: file)
    let originalRevision = try revision(in: originalJSON)
    let originalWrites = writer.writeCount
    let originalSecretsSaved = secrets.saveCount
    var unsupported = try tradingConfiguration(model: "invalid")
    unsupported.version = 1
    try verifyThrows(
        {
            try store.save(
                configuration: unsupported, revision: fakeEngineRevision(unsupported),
                secrets: tradingCredentials(token: "replacement-secret"), when: .paused
            )
        },
        matching: {
            if case TradingConfigurationStoreError.invalidConfiguration = $0 { return true }
            return false
        },
        "unsupported configuration version was saved"
    )
    try check(writer.writeCount == originalWrites, "invalid version wrote a configuration")
    try check(secrets.saveCount == originalSecretsSaved, "invalid version wrote credentials")
    try check(try Data(contentsOf: file) == originalJSON, "invalid version changed the saved file")
    try check(try secrets.load(revision: originalRevision) == credentials, "old revision changed")
    try check(try store.load()?.configuration == original, "invalid version made the profile unreadable")
}

private func failedFileCommitKeepsPriorPair() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let writer = ControlledConfigurationWriter()
    let store = TradingConfigurationStore(url: file, secrets: secrets, writer: writer)
    let original = try tradingConfiguration(model: "original")
    let originalSecrets = tradingCredentials(token: "original-secret")
    try store.save(configuration: original, revision: fakeEngineRevision(original), secrets: originalSecrets, when: .paused)
    let originalJSON = try Data(contentsOf: file)
    let originalRevision = try revision(in: originalJSON)

    writer.shouldFail = true
    try verifyThrows(
        {
            try store.save(
                configuration: try tradingConfiguration(model: "replacement"),
                revision: String(repeating: "a", count: 64),
                secrets: tradingCredentials(token: "replacement-secret"), when: .paused
            )
        },
        matching: {
            if case TradingConfigurationStoreError.unavailable = $0 { return true }
            return false
        },
        "failed configuration commit did not report a write error"
    )
    try check(try Data(contentsOf: file) == originalJSON, "failed commit changed saved reference")
    try check(try store.load()?.configuration == original, "failed commit changed saved policy")
    try check(try store.load()?.secrets == originalSecrets, "failed commit changed active credentials")
    try check(try secrets.load(revision: originalRevision) == originalSecrets, "old revision was deleted")
    try check(secrets.revisions.count == 1, "uncommitted credential revision was retained")
}

private func activeStateRejectsBeforeWrites() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let writer = ControlledConfigurationWriter()
    let store = TradingConfigurationStore(url: file, secrets: secrets, writer: writer)

    for state in [TradingRunState.starting, .running, .degraded, .pausing, .failed] {
        try verifyThrows(
            {
                try store.save(
                    configuration: try tradingConfiguration(model: "blocked"),
                    revision: String(repeating: "a", count: 64),
                    secrets: tradingCredentials(token: "blocked-secret"), when: state
                )
            },
            matching: {
                if case TradingConfigurationStoreError.activeProcessing = $0 { return true }
                return false
            },
            "active processing accepted trading settings save"
        )
    }
    try check(secrets.saveCount == 0, "active save wrote a credential revision")
    try check(writer.writeCount == 0, "active save wrote a configuration file")
    try check(try store.load() == nil, "active save created a configuration")
}

private func successfulReplacementChangesReference() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let store = TradingConfigurationStore(url: file, secrets: secrets)
    try store.save(
        configuration: try tradingConfiguration(model: "original"),
        revision: String(repeating: "a", count: 64),
        secrets: tradingCredentials(token: "original-secret"), when: .paused
    )
    let originalRevision = try revision(in: Data(contentsOf: file))

    let replacement = try tradingConfiguration(model: "replacement")
    let replacementSecrets = tradingCredentials(token: "replacement-secret")
    try store.save(configuration: replacement, revision: fakeEngineRevision(replacement), secrets: replacementSecrets, when: .paused)
    let json = try Data(contentsOf: file)
    let replacementRevision = try revision(in: json)
    try check(replacementRevision != originalRevision, "replacement reused a secret revision")
    try check(try store.load()?.configuration == replacement, "replacement policy was not loaded")
    try check(try store.load()?.secrets == replacementSecrets, "replacement credentials were not loaded")
    try check(try secrets.load(revision: originalRevision) == nil, "old credentials were not cleaned up")
    try check(try secrets.load(revision: replacementRevision) == replacementSecrets, "new revision was not stored")
    try check(
        try store.loadCredentialRevision(replacementRevision.uuidString) == replacementSecrets,
        "restore credential lookup did not load the exact immutable Keychain revision"
    )
    let text = String(decoding: json, as: UTF8.self)
    try check(!text.contains("replacement-secret") && !text.contains("original-secret"), "JSON contains secrets")
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
    try check((permissions as? NSNumber)?.intValue == 0o600, "saved file permissions are not 0600")
}

private func pendingActivationSurvivesStoreReopenAndFinalizesOnCommit() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let store = TradingConfigurationStore(url: file, secrets: secrets)
    let prior = try tradingConfiguration(model: "prior")
    let priorSecrets = tradingCredentials(token: "prior-secret")
    try store.save(configuration: prior, revision: fakeEngineRevision(prior), secrets: priorSecrets, when: .paused)
    let priorSecretRevision = try revision(in: Data(contentsOf: file))
    let candidate = try tradingConfiguration(model: "candidate")
    let candidateSecrets = tradingCredentials(token: "candidate-secret")
    let activationID = UUID().uuidString.lowercased()
    try store.stageValidatedActivation(
        configuration: candidate,
        revision: fakeEngineRevision(candidate),
        secrets: candidateSecrets,
        activationID: activationID,
        when: .paused
    )

    let reopened = TradingConfigurationStore(url: file, secrets: secrets)
    let pending = try reopened.pendingActivation()
    try check(pending?.activationID == activationID, "pending activation ID was lost on reopen")
    try check(pending?.candidateRevision == (fakeEngineRevision(candidate)), "candidate revision was lost on reopen")
    try check(try reopened.load()?.configuration == prior, "pending candidate replaced the stable config view")
    try check(secrets.revisions.count == 2, "pending candidate did not retain both credential revisions")

    try reopened.finalizeValidatedActivation(activationID: activationID)
    try check(try reopened.pendingActivation() == nil, "committed activation remained pending")
    try check(try reopened.load()?.configuration == candidate, "committed candidate was not published")
    try check(try reopened.load()?.secrets == candidateSecrets, "committed credentials were not published")
    try check(
        try secrets.load(revision: priorSecretRevision) == nil,
        "prior credentials remained after durable activation acknowledgement")
}

private func pendingActivationSurvivesStoreReopenAndRollsBackOnlyOnRequest() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let store = TradingConfigurationStore(url: file, secrets: secrets)
    let prior = try tradingConfiguration(model: "prior")
    let priorSecrets = tradingCredentials(token: "prior-secret")
    try store.save(configuration: prior, revision: fakeEngineRevision(prior), secrets: priorSecrets, when: .paused)
    let candidate = try tradingConfiguration(model: "candidate")
    let activationID = UUID().uuidString.lowercased()
    try store.stageValidatedActivation(
        configuration: candidate,
        revision: fakeEngineRevision(candidate),
        secrets: tradingCredentials(token: "candidate-secret"),
        activationID: activationID,
        when: .paused
    )
    let reopened = TradingConfigurationStore(url: file, secrets: secrets)

    try check(try reopened.load()?.configuration == prior, "unresolved activation displaced prior config")
    try reopened.rollbackValidatedActivation(activationID: activationID)
    try check(try reopened.pendingActivation() == nil, "rollback left a pending journal")
    try check(try reopened.load()?.configuration == prior, "rollback did not restore prior config")
    try check(try reopened.load()?.secrets == priorSecrets, "rollback did not restore prior credentials")
    try check(secrets.revisions.count == 1, "rollback retained the candidate credential revision")
}

private func temporaryTradingFile() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "trading-persistence-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "configuration.json")
}

private func tradingConfiguration(model: String) throws -> TradingConfiguration {
    let profile = try TradingProfileBuilder().build(
        TradingProfileDraft(
            guruID: "test-guru", displayName: "Test Guru", prefix: "ALERT:",
            exitBasis: .originalPosition
        ))
    return TradingConfiguration(
        source: TradingSourceConfiguration(channelIDs: ["channel"]),
        provider: TradingProviderConfiguration(name: .anthropic, model: model),
        accounts: [TradingAccountConfiguration(id: "paper", environment: .paper)],
        profiles: [profile],
        routes: []
    )
}

private func tradingCredentials(token: String) -> TradingSecrets {
    TradingSecrets(
        discordToken: token, providerAPIKey: token,
        brokers: [TradingBrokerCredentials(accountID: "paper", key: token, secret: token)]
    )
}

private func revision(in json: Data) throws -> UUID {
    guard let envelope = try JSONSerialization.jsonObject(with: json) as? [String: Any],
        let value = envelope["secretRevision"] as? String,
        let revision = UUID(uuidString: value)
    else {
        throw VerificationFailure(description: "configuration has no valid secret revision")
    }
    return revision
}

private final class MemorySecretRevisions: TradingSecretRevisionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: TradingSecrets] = [:]
    private var writes = 0

    var revisions: Set<UUID> { lock.withLock { Set(values.keys) } }
    var saveCount: Int { lock.withLock { writes } }

    func load(revision: UUID) throws -> TradingSecrets? {
        lock.withLock { values[revision] }
    }

    func save(_ secrets: TradingSecrets, for revision: UUID) throws {
        lock.withLock {
            values[revision] = secrets
            writes += 1
        }
    }

    func delete(revision: UUID) throws {
        _ = lock.withLock { values.removeValue(forKey: revision) }
    }
}

private final class ControlledConfigurationWriter: TradingConfigurationWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var fail = false
    private var writes = 0

    var shouldFail: Bool {
        get { lock.withLock { fail } }
        set { lock.withLock { fail = newValue } }
    }
    var writeCount: Int { lock.withLock { writes } }

    func write(_ data: Data, to url: URL) throws {
        let failing = lock.withLock {
            writes += 1
            return fail
        }
        if failing { throw ControlledWriteFailure() }
        try AtomicTradingConfigurationWriter().write(data, to: url)
    }
}

private struct ControlledWriteFailure: Error {}

private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw VerificationFailure(description: message) }
}
