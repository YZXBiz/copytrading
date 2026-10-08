/// One stop of the setup tour: what it points at and what it asks for. The tour never keeps its
/// own place: the stop is read from the setup as it stands and the panel that is open, so typing,
/// pasting, or connecting moves it on by itself.
enum SetupTourStop: Int, CaseIterable, Identifiable {
    case discordRow
    case channelIDs
    case discordToken
    case interpreterServices
    case interpreterKey
    case accounts
    case gurus
    case startCopying

    var id: Int { rawValue }

    /// The stop for a setup this far along, with this Connections panel open; nil once copying
    /// has started. `channelsEntered`: a channel is in and the typing has paused, so the tour
    /// doesn't jump away on the first digit. `panelConnected`: the open panel's service already
    /// reads Connected, so its sheet asks for nothing and the tour stays on its next step.
    static func current(
        progress: SetupProgress, channelsEntered: Bool, panel: ConnectionKind?, panelConnected: Bool = false
    ) -> SetupTourStop? {
        let panel = panelConnected ? nil : panel
        if panel == .discord {
            return channelsEntered ? .discordToken : .channelIDs
        }
        if !progress.isDone(.discord) { return .discordRow }
        if panel == .interpreter { return .interpreterKey }
        if !progress.isDone(.interpreter) { return .interpreterServices }
        if !progress.isDone(.account) { return .accounts }
        if !progress.isDone(.guru) { return .gurus }
        if !progress.isDone(.start) { return .startCopying }
        return nil
    }

    var target: SetupTourTarget {
        switch self {
        case .discordRow: .discordRow
        case .channelIDs: .channelIDs
        case .discordToken: .discordToken
        case .interpreterServices: .interpreterServices
        case .interpreterKey: .interpreterKey
        case .accounts: .accounts
        case .gurus: .gurus
        case .startCopying: .startCopying
        }
    }

    /// The checklist step this stop belongs to, for its help and the strip.
    var step: SetupStep {
        switch self {
        case .discordRow, .channelIDs, .discordToken: .discord
        case .interpreterServices, .interpreterKey: .interpreter
        case .accounts: .account
        case .gurus: .guru
        case .startCopying: .start
        }
    }

    var title: String {
        switch self {
        case .discordRow: "Connect Discord"
        case .channelIDs: "Paste the channel ID"
        case .discordToken: "Paste your Discord token"
        case .interpreterServices: "Pick an AI reader"
        case .interpreterKey: "Paste the API key"
        case .accounts: "Add your broker"
        case .gurus: "Add your guru"
        case .startCopying: "Start copying"
        }
    }

    /// The italic second line under the title.
    var subtitle: String {
        switch self {
        case .discordRow: "where your guru posts"
        case .channelIDs: "of your guru's channel"
        case .discordToken, .interpreterKey: "and connect it"
        case .interpreterServices: "it reads every post"
        case .accounts: "start with paper money"
        case .gurus: "and the account they fill"
        case .startCopying: "everything is checked first"
        }
    }

    var detail: String {
        switch self {
        case .discordRow: "Open the Discord row. You'll paste the guru's channel ID and your Discord token there."
        case .channelIDs:
            "In Discord, right-click the channel › **Copy Channel ID**. Missing? Turn on **Developer Mode** in Discord's Advanced settings."
        case .discordToken: "Then click the blue button below; CopyTrading checks it with Discord. **Help** shows where to find it."
        case .interpreterServices: "Pick a service you have a key for. DeepSeek costs the least."
        case .interpreterKey: "Then click the blue button below; CopyTrading tries the key. It stays in this Mac's Keychain."
        case .accounts: "Open the paper account and paste its two Alpaca keys. **Help** shows where Alpaca keeps them."
        case .gurus: "Give them a name and choose the account that copies them."
        case .startCopying: "Click **Start Copying**. Each connection is tested and your examples are read before anything is saved."
        }
    }

    /// What moves the tour on, shown under the instruction.
    var waiting: String {
        switch self {
        case .discordRow: "Waiting for you to open it"
        case .discordToken, .interpreterKey: "Moves on once it connects"
        case .channelIDs: "Moves on once an ID is in"
        case .interpreterServices: "Waiting for you to pick one"
        case .accounts: "Waiting for the account's keys"
        case .gurus: "Waiting for a guru"
        case .startCopying: "Waiting for Start Copying"
        }
    }

    /// A stop inside a Connections panel: its hint sits in the panel under the field, not in a
    /// card over it.
    var isInPanel: Bool {
        self == .channelIDs || self == .discordToken || self == .interpreterKey
    }

    /// A key field's card sits above it, so the check's result and the button under the field
    /// stay in view; the channel field's card sits below, over fields not needed yet.
    var prefersAbove: Bool {
        self == .discordToken || self == .interpreterKey
    }

    /// Rows are pointed at near their trailing action; fields near where typing starts.
    var pointsAtTrailingEdge: Bool {
        switch self {
        case .discordRow, .interpreterServices, .accounts, .gurus, .startCopying: true
        case .channelIDs, .discordToken, .interpreterKey: false
        }
    }
}
