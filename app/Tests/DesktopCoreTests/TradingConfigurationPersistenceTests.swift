import CryptoKit
import DesktopCore
import Foundation
import Testing

func runTradingConfigurationPersistenceTests() throws {
    try failedFileCommitKeepsPriorPair()
    try activeStateRejectsBeforeWrites()
    try unsupportedVersionRejectsBeforeWrites()
    try olderVersionIsDiscardedNotMigrated()
    try savedFileHasTheFieldsBackupsRead()
    try successfulReplacementChangesReference()
    try pendingActivationSurvivesStoreReopenAndFinalizesOnCommit()
    try pendingActivationSurvivesStoreReopenAndRollsBackOnlyOnRequest()
}

/// The engine's backup reads this file and refuses fields it does not know
/// (`SAVED_CONFIGURATION_FIELDS` in `engine/src/copytrading_engine/backup/configuration.py`).
private func savedFileHasTheFieldsBackupsRead() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = TradingConfigurationStore(url: file, secrets: MemorySecretRevisions())
    let configuration = try tradingConfiguration(model: "fields")
    try store.save(
        configuration: configuration, revision: fakeEngineRevision(configuration), secrets: tradingCredentials(token: "fields"),
        when: .paused)
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
    try #require(
        Set(saved.keys) == ["version", "configuration", "revision", "secretRevision"],
        "the saved setup's fields changed; update the engine's backup reader too: \(saved.keys.sorted())")
}

/// Nothing is deleted: a current setup stays, one the next launch upgrades stays, and one from
/// before upgrades moves aside with its keys so a new setup can be saved.
private func olderVersionIsDiscardedNotMigrated() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let store = TradingConfigurationStore(url: file, secrets: secrets)
    let movedMissing = try store.setAsideBeforeUpgrades()
    try #require(!movedMissing, "a missing setup file was reported as set aside")
    let current = try tradingConfiguration(model: "current")
    try store.save(
        configuration: current, revision: fakeEngineRevision(current), secrets: tradingCredentials(token: "current"), when: .paused)
    let movedCurrent = try store.setAsideBeforeUpgrades()
    let currentLoaded = try store.load()
    try #require(!movedCurrent, "a current setup was set aside")
    try #require(store.olderVersion() == nil, "a current setup read as earlier")
    try #require(currentLoaded != nil, "a current setup stopped loading")

    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
    guard let secretRevision = UUID(uuidString: saved["secretRevision"] as? String ?? "") else {
        throw VerificationFailure(description: "the saved setup had no secret revision")
    }
    func writeVersion(_ version: Int) throws {
        var older = saved
        var configuration = saved["configuration"] as? [String: Any] ?? [:]
        configuration["version"] = version
        older["configuration"] = configuration
        try JSONSerialization.data(withJSONObject: older).write(to: file)
    }

    try writeVersion(SetupUpgrade.earliestVersion)
    let movedUpgradable = try store.setAsideBeforeUpgrades()
    try #require(!movedUpgradable, "a setup the next launch upgrades was set aside")
    try #require(store.olderVersion() == SetupUpgrade.earliestVersion, "an earlier setup wasn't noticed")

    try writeVersion(SetupUpgrade.earliestVersion - 1)
    let movedOlder = try store.setAsideBeforeUpgrades()
    let keptSecrets = try secrets.load(revision: secretRevision)
    let loadedAfter = try store.load()
    try #require(movedOlder, "a setup from before upgrades stayed in the way of a new one")
    try #require(FileManager.default.fileExists(atPath: store.setAsideURL.path), "the older setup was deleted")
    try #require(keptSecrets != nil, "the older setup's Keychain item was deleted")
    try #require(loadedAfter == nil, "the app did not start clean after setting an older setup aside")
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
            guruID: "test-guru", displayName: "Test Guru"
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

/// A setup the last version saved, as it wrote it: every field the same, the after-restart choice
/// still in the account's record.
private func writeVersion9(of configuration: TradingConfiguration, to store: TradingConfigurationStore) throws {
    try store.save(
        configuration: configuration, revision: fakeEngineRevision(configuration),
        secrets: tradingCredentials(token: "kept"), when: .paused)
    var saved = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any] ?? [:]
    var raw = saved["configuration"] as? [String: Any] ?? [:]
    raw["version"] = 9
    raw["accounts"] = (raw["accounts"] as? [[String: Any]] ?? []).map { account in
        var account = account
        var policy = account["policy"] as? [String: Any] ?? [:]
        policy.removeValue(forKey: "recovery_preference")
        account["policy"] = policy
        return account
    }
    saved["configuration"] = raw
    try JSONSerialization.data(withJSONObject: saved).write(to: store.url)
}

@Test func aSetupTheLastVersionSavedIsUpgradedWithItsKeysAndChoices() async throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = TradingConfigurationStore(url: file, secrets: MemorySecretRevisions())
    // The signal age the last version saved, not today's default for a new setup (600 s).
    var expected = try tradingConfiguration(model: "deepseek-flash")
    expected.accounts[0].policy.maxSignalAgeSeconds = 120
    try writeVersion9(of: expected, to: store)
    #expect(store.olderVersion() == 9)
    #expect(throws: TradingConfigurationStoreError.self) { try store.load() }

    let upgraded = try await store.upgradeOlderVersion(
        facts: SetupUpgrade.Facts(recoveryPreferences: ["paper": .automatic])
    ) { fakeEngineRevision($0) }

    expected.accounts[0].policy.recoveryPreference = .automatic
    #expect(upgraded == expected)
    #expect(upgraded.accounts[0].policy.maxSignalAgeSeconds == 120)
    #expect(TradingAccountPolicy().maxSignalAgeSeconds == 600, "a new setup's buys lost the 10-minute signal age")
    let loaded = try #require(try store.load())
    #expect(loaded.configuration == expected)
    #expect(loaded.secrets == tradingCredentials(token: "kept"))
    #expect(store.olderVersion() == nil)
}

@Test func anAccountWhoseRecordSaysNothingWaitsForTheOwnerAfterARestart() throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = TradingConfigurationStore(url: file, secrets: MemorySecretRevisions())
    try writeVersion9(of: try tradingConfiguration(model: "m"), to: store)
    let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
    let upgraded = try SetupUpgrade.upgrade(raw["configuration"] as? [String: Any] ?? [:], facts: .init())
    #expect(upgraded.version == TradingConfiguration.currentVersion)
    #expect(upgraded.accounts[0].policy.recoveryPreference == .manual)
}

@Test func onlySetupsTheStepsReachAreUpgraded() throws {
    #expect(throws: SetupUpgrade.Failure.tooOld(7)) {
        try SetupUpgrade.upgrade(["version": 7], facts: .init())
    }
    #expect(throws: SetupUpgrade.Failure.tooNew(TradingConfiguration.currentVersion + 1)) {
        try SetupUpgrade.upgrade(["version": TradingConfiguration.currentVersion + 1], facts: .init())
    }
    #expect(throws: SetupUpgrade.Failure.unreadable) {
        try SetupUpgrade.upgrade(["version": 9, "accounts": "none"], facts: .init())
    }
}

@Test func eachGuruTakesTheIDItsChannelGivesItAndKeepsItsPlaybook() async throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = TradingConfigurationStore(url: file, secrets: MemorySecretRevisions())
    let random = try TradingProfileBuilder().build(
        TradingProfileDraft(guruID: "guru-445d352c", displayName: "赵哥", playbook: "加了6分之一常规仓 buys a sixth"))
    var configuration = try tradingConfiguration(model: "m")
    configuration.source = TradingSourceConfiguration(channelIDs: ["1517754775674949742"])
    configuration.profiles = [random]
    configuration.routes = [
        TradingRouteConfiguration(
            channelID: "1517754775674949742", guruID: random.guruID, profileRevision: random.profileRevision,
            connections: [TradingRouteConnection(accountID: "paper", fullPositionUSD: "600")])
    ]
    try writeVersion9(of: configuration, to: store)

    let upgraded = try await store.upgradeOlderVersion(facts: .init()) { fakeEngineRevision($0) }

    let profile = try #require(upgraded.profiles.first)
    let route = try #require(upgraded.routes.first)
    #expect(profile.guruID == "guru-3909e2aa")
    #expect(route.guruID == "guru-3909e2aa")
    #expect(route.profileRevision == profile.profileRevision)
    #expect(profile.profileRevision != random.profileRevision)
    #expect((profile.displayName, profile.playbook) == (random.displayName, random.playbook))
    #expect(
        profile
            == (try TradingProfileBuilder().build(
                TradingProfileDraft(guruID: "guru-3909e2aa", displayName: "赵哥", playbook: random.playbook))))
}

/// A setup as 0.1.0-beta.5 saved it: version 8, a profile with examples, its revision built with
/// them (`git show 52ac8535^:app/Sources/DesktopCore/TradingContracts.swift`).
private func writeVersion8(to store: TradingConfigurationStore) throws -> (TradingConfiguration, TradingSecrets) {
    let examples: [[String: Any]] = [
        [
            "message": "5.90加了6分之一常规仓soun", "expected_action": "buy", "expected_symbol": "SOUN",
            "expected_fraction": "0.1666", "expected_price": "5.90", "expected_buy_price": NSNull(),
        ]
    ]
    let base: [String: Any] = [
        "guru_id": "guru-445d352c", "display_name": "赵哥", "playbook": "加了 means buy", "examples": examples,
    ]
    let hashed = try JSONSerialization.data(withJSONObject: base, options: [.sortedKeys, .withoutEscapingSlashes])
    let v8Revision = SHA256.hash(data: hashed).map { String(format: "%02x", $0) }.joined()
    var profile = base
    profile["profile_revision"] = v8Revision
    var policy = TradingAccountPolicy()
    policy.maxOrderUSD = "200"
    policy.maxSymbolUSD = "1000"
    policy.maxSignalAgeSeconds = 120  // beta.5's default; an upgraded setup keeps it
    var policyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(policy)) as? [String: Any] ?? [:]
    policyJSON.removeValue(forKey: "recovery_preference")
    // The source and model service as the app wrote them then; their shape hasn't changed since.
    let source = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(TradingSourceConfiguration(channelIDs: ["1517754775674949742"])))
    let provider = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(TradingProviderConfiguration(name: .deepseek, model: "deepseek-flash")))
    let configuration: [String: Any] = [
        "version": 8,
        "source": source,
        "provider": provider,
        "accounts": [["id": "zhap-account-2", "environment": "paper", "policy": policyJSON]],
        "profiles": [profile],
        "routes": [
            [
                "source": "discord", "channel_id": "1517754775674949742", "guru_id": "guru-445d352c",
                "profile_revision": v8Revision,
                "connections": [["account_id": "zhap-account-2", "full_position_usd": "1000"]],
                "repeat_window_minutes": 10,
            ]
        ],
    ]
    let secrets = TradingSecrets(
        discordToken: "token", providerAPIKey: "key",
        brokers: [TradingBrokerCredentials(accountID: "zhap-account-2", key: "k", secret: "s")])
    let secretRevision = UUID()
    let envelope: [String: Any] = [
        "version": 1, "configuration": configuration, "revision": String(repeating: "a", count: 64),
        "secretRevision": secretRevision.uuidString,
    ]
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: envelope).write(to: store.url)
    var expected = try JSONDecoder().decode(
        TradingConfiguration.self,
        from: JSONSerialization.data(withJSONObject: [
            "version": 10,
            "source": source,
            "provider": provider,
            "accounts": [
                ["id": "zhap-account-2", "environment": "paper", "policy": policyJSON.merging(["recovery_preference": "automatic"]) { $1 }]
            ],
            "profiles": [], "routes": [],
        ]))
    let rebuilt = try TradingProfileBuilder().build(
        TradingProfileDraft(guruID: "guru-3909e2aa", displayName: "赵哥", playbook: "加了 means buy"))
    expected.profiles = [rebuilt]
    expected.routes = [
        TradingRouteConfiguration(
            channelID: "1517754775674949742", guruID: "guru-3909e2aa", profileRevision: rebuilt.profileRevision,
            connections: [TradingRouteConnection(accountID: "zhap-account-2", fullPositionUSD: "1000")])
    ]
    return (expected, secrets)
}

@Test func aSetupBeta5SavedReachesThisVersionWithEverythingItHad() async throws {
    let file = temporaryTradingFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let secrets = MemorySecretRevisions()
    let store = TradingConfigurationStore(url: file, secrets: secrets)
    let (expected, credentials) = try writeVersion8(to: store)
    let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
    let secretRevision = try #require(UUID(uuidString: raw["secretRevision"] as? String ?? ""))
    try secrets.save(credentials, for: secretRevision)
    #expect(store.olderVersion() == 8)
    #expect(try !store.setAsideBeforeUpgrades())

    let upgraded = try await store.upgradeOlderVersion(
        facts: SetupUpgrade.Facts(recoveryPreferences: ["zhap-account-2": .automatic])
    ) { fakeEngineRevision($0) }

    #expect(upgraded == expected)
    let loaded = try #require(try store.load())
    #expect(loaded.configuration == expected)
    #expect(loaded.secrets == credentials)
    let rewritten = try String(contentsOf: file, encoding: .utf8)
    #expect(!rewritten.contains("examples"), "the examples outlived the upgrade")
}
