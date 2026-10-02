import Foundation

/// A short how-to: numbered steps, an optional caution, and where to go. Steps may use
/// **bold** for the names of buttons and menus, as the guide and the popovers both show them.
struct HelpArticle: Identifiable, Hashable {
    struct Destination: Hashable {
        let title: String
        let url: URL
    }

    let id: String
    let title: String
    var intro: String?
    let steps: [String]
    var caution: String?
    var destination: Destination?
}
