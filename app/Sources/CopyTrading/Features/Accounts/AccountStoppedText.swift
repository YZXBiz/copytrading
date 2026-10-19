/// What the owner is told when an account stops on its own: which account, and what to do. Plain
/// words, never the engine's code for the cause.
@MainActor
enum AccountStoppedText {
    static func title(_ accountID: String) -> String {
        L10n.string("Copying into %@ stopped", accountID)
    }

    static var body: String {
        L10n.string("CopyTrading hit a problem it couldn't fix. Stop copying everywhere, then start again to reopen it.")
    }
}
