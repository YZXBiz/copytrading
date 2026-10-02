import CryptoKit
import DesktopCore
import Foundation

/// Stands in for the engine's configuration revision. It is salted so it can never equal a
/// hash the app computes itself: every revision the app stores must come from the engine.
func fakeEngineRevision(_ configuration: TradingConfiguration) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = (try? encoder.encode(configuration)) ?? Data()
    return SHA256.hash(data: Data("engine:".utf8) + data).map { String(format: "%02x", $0) }.joined()
}
