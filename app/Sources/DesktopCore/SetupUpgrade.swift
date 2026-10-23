import Foundation

/// A saved setup is the owner's data, so a change to its shape never makes them set up again
/// (ADR-0013). Each version change ships one step here that rewrites the version before it; the
/// app runs the steps once at launch and saves the result. Nothing else reads an old shape.
public enum SetupUpgrade {
    /// The oldest saved setup the steps reach: 0.1.0-beta.5's. Anything older predates upgrades.
    public static let earliestVersion = 8

    /// What a step needs that the saved file doesn't hold, read from the engine first.
    public struct Facts: Sendable, Equatable {
        /// Each account's after-restart choice, from its record, for setups saved before the
        /// choice moved into the setup.
        public var recoveryPreferences: [String: RecoveryPreference]

        public init(recoveryPreferences: [String: RecoveryPreference] = [:]) {
            self.recoveryPreferences = recoveryPreferences
        }
    }

    public enum Failure: Error, Equatable, Sendable, LocalizedError {
        /// The file's shape is not one the steps know.
        case unreadable
        /// Older than the earliest step.
        case tooOld(Int)
        /// Newer than this CopyTrading.
        case tooNew(Int)

        public var errorDescription: String? {
            switch self {
            case .unreadable: "The saved setup isn't in a shape CopyTrading knows."
            case .tooOld: "The saved setup is from before CopyTrading could carry setups over."
            case .tooNew: "The saved setup is from a newer CopyTrading."
            }
        }
    }

    /// The saved `configuration` object at the current version.
    public static func upgrade(_ configuration: [String: Any], facts: Facts) throws -> TradingConfiguration {
        var raw = configuration
        guard var version = raw["version"] as? Int else { throw Failure.unreadable }
        guard version >= earliestVersion else { throw Failure.tooOld(version) }
        guard version <= TradingConfiguration.currentVersion else { throw Failure.tooNew(version) }
        while version < TradingConfiguration.currentVersion {
            switch version {
            case 8: raw = try from8(raw)
            case 9: raw = try from9(raw, facts: facts)
            default: throw Failure.unreadable
            }
            version += 1
            raw["version"] = version
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: raw)
            return try JSONDecoder().decode(TradingConfiguration.self, from: data)
        } catch {
            throw Failure.unreadable
        }
    }

    /// 8 → 9: guru examples are gone; a profile is its name and playbook, and its revision is
    /// built again without them.
    static func from8(_ configuration: [String: Any]) throws -> [String: Any] {
        try rebuildingProfiles(configuration) { $0 }
    }

    /// 9 → 10: what an account does after a restart moved from its record into its limits, and
    /// each guru takes the ID its channel gives it, so setting up again keeps their history.
    static func from9(_ configuration: [String: Any], facts: Facts) throws -> [String: Any] {
        var raw = configuration
        guard let accounts = raw["accounts"] as? [[String: Any]], let routes = raw["routes"] as? [[String: Any]]
        else { throw Failure.unreadable }
        raw["accounts"] = try accounts.map { account in
            guard let id = account["id"] as? String else { throw Failure.unreadable }
            var upgraded = account
            var policy = account["policy"] as? [String: Any] ?? [:]
            policy["recovery_preference"] = (facts.recoveryPreferences[id] ?? .manual).rawValue
            upgraded["policy"] = policy
            return upgraded
        }
        var guruIDs: [String: String] = [:]
        for route in routes {
            guard let old = route["guru_id"] as? String, let channel = route["channel_id"] as? String else {
                throw Failure.unreadable
            }
            guruIDs[old] = GuruIdentity.id(channelID: channel, source: route["source"] as? String ?? "discord")
        }
        return try rebuildingProfiles(raw) { guruIDs[$0] ?? $0 }
    }

    /// Every profile built again from its guru ID (renamed by `guruID`), name and playbook, and
    /// every route pointed at its profile's new revision. A profile's revision fingerprints all
    /// three, so any change to a profile's shape or its guru's ID goes through here.
    private static func rebuildingProfiles(
        _ configuration: [String: Any], guruID: (String) -> String
    ) throws -> [String: Any] {
        var raw = configuration
        guard let profiles = raw["profiles"] as? [[String: Any]], let routes = raw["routes"] as? [[String: Any]]
        else { throw Failure.unreadable }
        var revisions: [String: String] = [:]
        raw["profiles"] = try profiles.map { profile in
            guard let old = profile["guru_id"] as? String, let name = profile["display_name"] as? String,
                let revision = profile["profile_revision"] as? String
            else { throw Failure.unreadable }
            let rebuilt = try TradingProfileBuilder().build(
                TradingProfileDraft(
                    guruID: guruID(old), displayName: name, playbook: profile["playbook"] as? String ?? ""))
            revisions[revision] = rebuilt.profileRevision
            return [
                "guru_id": rebuilt.guruID, "display_name": rebuilt.displayName, "playbook": rebuilt.playbook,
                "profile_revision": rebuilt.profileRevision,
            ]
        }
        raw["routes"] = routes.map { route in
            var upgraded = route
            if let old = route["guru_id"] as? String { upgraded["guru_id"] = guruID(old) }
            if let old = route["profile_revision"] as? String, let new = revisions[old] {
                upgraded["profile_revision"] = new
            }
            return upgraded
        }
        return raw
    }
}
