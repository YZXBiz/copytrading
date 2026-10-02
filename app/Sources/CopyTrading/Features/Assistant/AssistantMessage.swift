import DesktopCore
import Foundation

/// One entry in the assistant transcript: what the owner asked, or what the assistant answered.
struct AssistantMessage: Identifiable, Equatable {
    enum Author { case owner, assistant }

    let id: UUID
    let author: Author
    var text: String
    var steps: [String]
    var links: [AssistantLink]
    var proposalIDs: [String]
    var errorText: String?

    init(
        id: UUID = UUID(), author: Author, text: String = "", steps: [String] = [], links: [AssistantLink] = [],
        proposalIDs: [String] = [], errorText: String? = nil
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.steps = steps
        self.links = links
        self.proposalIDs = proposalIDs
        self.errorText = errorText
    }
}
