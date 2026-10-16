import DesktopCore

extension ConnectionsDraft {
    /// What Connect says when a panel has nothing it could check or keep, in the owner's words;
    /// nil once anything is entered. A half-filled panel still closes, and its row says what is
    /// missing, so the owner can come back for the rest.
    @MainActor
    func missingToConnect(_ kind: ConnectionKind, savedSecret: Bool) -> String? {
        switch kind {
        case .discord:
            guard sourceChannelIDs.isEmpty, discordToken.isEmpty, !savedSecret else { return nil }
            return L10n.string("Enter a channel ID and your Discord token to connect.")
        case .interpreter:
            guard modelName.trimmed.isEmpty else { return nil }
            return L10n.string("Enter the model's name to connect.")
        case .alerts:
            return missingForAlerts(savedSecret: savedSecret)
        }
    }
}
