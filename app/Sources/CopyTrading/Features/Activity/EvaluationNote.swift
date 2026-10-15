import DesktopCore
import Foundation

/// The model's own note on an evaluated post, when it adds something: a known reason in words or
/// free text, but not a parser code and not the post's own words repeated back.
enum EvaluationNote {
    @MainActor static func text(_ evaluation: ProfileEvaluation, post: String) -> String? {
        guard let note = Reason.parserMessage(evaluation.reason, needsReview: evaluation.decision == "review") else {
            return nil
        }
        return comparable(note) == comparable(post) ? nil : note
    }

    private static func comparable(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
