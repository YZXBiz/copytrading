import Foundation

/// A guru as the owner knows them: the id the engine records, and the name the app shows.
public struct AssistantGuru: Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// What the owner was looking at when they asked, so the assistant can resolve "this guru", the
/// gurus by name, and the app's language (`en` or `zh-Hans`), which the answer falls back to.
public struct AssistantAskContext: Codable, Equatable, Sendable {
    /// The engine reads at most this many gurus.
    public static let maxGurus = 50

    public var screen: String
    public var selectedSourceID: String?
    public var selectedAccountID: String?
    public var selectedGuruID: String?
    public var language: String
    public var gurus: [AssistantGuru]

    public init(
        screen: String, selectedSourceID: String? = nil, selectedAccountID: String? = nil,
        selectedGuruID: String? = nil, language: String = "en", gurus: [AssistantGuru] = []
    ) {
        self.screen = screen
        self.selectedSourceID = selectedSourceID
        self.selectedAccountID = selectedAccountID
        self.selectedGuruID = selectedGuruID
        self.language = language
        self.gurus = Array(gurus.prefix(Self.maxGurus))
    }

    enum CodingKeys: String, CodingKey {
        case screen
        case selectedSourceID = "selected_source_id"
        case selectedAccountID = "selected_account_id"
        case selectedGuruID = "selected_guru_id"
        case language, gurus
    }

    /// The engine's request shape names every selection, `null` when there is none.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(screen, forKey: .screen)
        try container.encode(selectedSourceID, forKey: .selectedSourceID)
        try container.encode(selectedAccountID, forKey: .selectedAccountID)
        try container.encode(selectedGuruID, forKey: .selectedGuruID)
        try container.encode(language, forKey: .language)
        try container.encode(gurus, forKey: .gurus)
    }
}

/// A thing in the app the assistant points at; the owner opens it from the transcript.
public struct AssistantLink: Codable, Equatable, Sendable {
    public let kind: String
    public let id: String
    public let title: String

    public init(kind: String, id: String, title: String) {
        self.kind = kind
        self.id = id
        self.title = title
    }
}

public struct AssistantEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text, step, link, proposal, error, done
    }

    public let seq: Int
    public let kind: Kind
    public let text: String?
    public let link: AssistantLink?
    public let proposalID: String?
    public let code: String?

    public init(
        seq: Int, kind: Kind, text: String? = nil, link: AssistantLink? = nil,
        proposalID: String? = nil, code: String? = nil
    ) {
        self.seq = seq
        self.kind = kind
        self.text = text
        self.link = link
        self.proposalID = proposalID
        self.code = code
    }

    enum CodingKeys: String, CodingKey {
        case seq, kind, text, link, code
        case proposalID = "proposal_id"
    }
}

public struct AssistantTurnPage: Codable, Equatable, Sendable {
    public let turnID: String
    public let done: Bool
    public let events: [AssistantEvent]

    public init(turnID: String, done: Bool, events: [AssistantEvent]) {
        self.turnID = turnID
        self.done = done
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case done, events
    }
}
