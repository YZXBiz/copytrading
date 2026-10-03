import DesktopCore
import Foundation
import Testing

func runTradingSecretRevisionDeletionTests() throws {
    let service = "com.copytrading.desktop.test.trading.\(UUID().uuidString)"
    let store = TradingKeychainStore(service: service)
    let revision = UUID()
    let secrets = TradingSecrets(discordToken: "discord", providerAPIKey: "model", brokers: [])
    try store.save(secrets, for: revision)
    let saved = try store.load(revision: revision)
    try #require(saved == secrets, "a saved revision must read back")
    try store.delete(revision: revision)
    let deleted = try store.load(revision: revision)
    try #require(deleted == nil, "a deleted revision must be gone")
    try store.delete(revision: revision)
}
