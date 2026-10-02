import Foundation

/// How an answer's light Markdown reads: bold, italics, and code as they would in a note; "- "
/// lines become bullets and "# " headings bold, while a "#NVDA" ticker tag stays as written.
/// Answers can quote what other people wrote, so nothing in them is a live link.
enum AssistantMarkdown {
    static func rendered(_ text: String) -> AttributedString {
        let source = text.components(separatedBy: "\n").map(line).joined(separator: "\n")
        var attributed =
            (try? AttributedString(
                markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
        for run in attributed.runs where run.link != nil {
            attributed[run.range].link = nil
        }
        return attributed
    }

    /// One line as inline Markdown: a bullet, a bold heading, or the line unchanged.
    static func line(_ line: String) -> String {
        let trimmed = line.drop { $0 == " " }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return "•\u{2002}" + trimmed.dropFirst(2) }
        if trimmed.range(of: #"^#{1,6} "#, options: .regularExpression) != nil {
            let heading = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            return heading.isEmpty ? "" : "**\(heading)**"
        }
        return line
    }
}
