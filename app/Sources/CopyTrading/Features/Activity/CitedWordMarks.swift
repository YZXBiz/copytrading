import Foundation

/// Where in a post the reader's cited words are (ADR-0007), so the card can mark them. A word that
/// appears more than once is marked where it sits nearest another cited word, since a call's words
/// sit together: in "现在179 … 建仓区域160-179", the range's 179 is the one beside 160.
enum CitedWordMarks {
    static func ranges(of words: [String], in text: String) -> [Range<String.Index>] {
        let cited = words.filter { !$0.isEmpty }
        let found = cited.map { occurrences(of: $0, in: text) }
        var marks: [Range<String.Index>] = []
        for (index, candidates) in found.enumerated() where !candidates.isEmpty {
            let others = found.enumerated().filter { $0.offset != index }.map(\.element)
            let best = candidates.min { lhs, rhs in
                nearest(lhs, to: others, in: text) < nearest(rhs, to: others, in: text)
            }
            if let best { marks.append(best) }
        }
        return marks
    }

    private static func occurrences(of word: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex, let range = text.range(of: word, range: start..<text.endIndex) {
            ranges.append(range)
            start = text.index(after: range.lowerBound)
        }
        return ranges
    }

    /// How far a candidate sits from the nearest other cited word.
    private static func nearest(
        _ candidate: Range<String.Index>, to others: [[Range<String.Index>]], in text: String
    ) -> Int {
        let at = text.distance(from: text.startIndex, to: candidate.lowerBound)
        return others.joined().map { abs(text.distance(from: text.startIndex, to: $0.lowerBound) - at) }.min() ?? 0
    }
}
