import CryptoKit
import Foundation

/// A guru's ID. Each channel has one guru, so the channel names them: setting up again, or
/// importing the same setup, gives the guru the same ID, and their posts and holdings stay theirs.
/// The engine names a post's guru the same way (`route_keys.guru_for_channel`).
public enum GuruIdentity {
    public static func id(channelID: String, source: String = "discord") -> String {
        let digest = SHA256.hash(data: Data("\(source):\(channelID)".utf8))
        return "guru-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
