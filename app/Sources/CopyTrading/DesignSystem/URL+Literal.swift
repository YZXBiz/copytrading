import Foundation

extension URL {
    /// A URL written into the app. A malformed literal is a programming error, caught the first
    /// time the screen that uses it is opened.
    init(literal: StaticString) {
        guard let url = URL(string: "\(literal)") else {
            preconditionFailure("Malformed URL literal \(literal)")
        }
        self = url
    }
}
