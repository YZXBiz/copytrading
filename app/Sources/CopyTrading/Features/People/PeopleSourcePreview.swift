import DesktopCore
import Foundation

/// A compact captured-source preview; the enclosing card owns navigation, including source links.
enum PeopleSourcePreview {
    static func text(for item: SourceActivity, dropping prefix: String? = nil) -> String {
        item.readableText(dropping: prefix)
    }

    static func formatted(_ text: String) -> AttributedString {
        ActivitySourceText.formattedPreview(text)
    }
}
