import DesktopCore
import Foundation

extension SourceActivity {
    /// What the interpreter decided, in the words a trader would use.
    @MainActor
    var decisionTitle: String {
        switch decision {
        case "trade": L10n.string("Trade")
        case "review": L10n.string("Needs review")
        case "ignore": L10n.string("Ignored")
        case let other?: L10n.string(Humanize.code(other))
        case nil:
            captureStatus == "historical"
                ? L10n.string("Historical")
                : L10n.string(Humanize.code(parseStatus))
        }
    }

    var decisionTone: StatusTone {
        switch decision {
        case "trade": .positive
        case "review": .caution
        case "ignore": .inactive
        default: captureStatus == "historical" ? .neutral : StatusTone(code: parseStatus)
        }
    }

    var needsManualReview: Bool {
        decision == "review" && captureStatus == "delivered"
    }

    var isHistorical: Bool {
        captureStatus == "historical"
    }
}

extension SourceActivity {
    /// What the post asked for, in plain words: "Buy ABC at $12.34".
    @MainActor
    var headline: String {
        guard let first = instructions.first else {
            switch decision {
            case "ignore": return L10n.string("Not a trade")
            case "review": return L10n.string("Needs your review")
            case "trade": return L10n.string("Trade with no instructions")
            default: return L10n.string(isHistorical ? "Earlier message" : "Reading the message…")
            }
        }
        let rest = instructions.count > 1 ? L10n.string(" and %lld more", Int64(instructions.count - 1)) : ""
        return first.phrase + rest
    }

    var sourceDate: Date? { Humanize.date(sourceAt) }

    /// A compact captured-source excerpt without mass mentions.
    func readableText() -> String {
        var source = readingText()
        if source.isEmpty, let embed = readableSourceEmbeds.first {
            // An embed-only post still has a source; retain its captured words and order.
            source =
                ([embed.title, embed.description].compactMap { $0 }
                + embed.fields.flatMap { [$0.name, $0.value] })
                .filter { ActivitySourceText.hasReadableText($0) }
                .joined(separator: " ")
        }
        return source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The source post with only mass mentions and outer whitespace removed.
    /// Unlike `readableText`, this keeps line breaks and paragraph spacing intact.
    func readingText() -> String {
        let source = sourceEvent.captureStatus == "complete" ? sourceEvent.content : text
        return withoutMassMentions(in: source).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var readableSourceEmbeds: [SourceEmbedEvidence] {
        guard sourceEvent.captureStatus == "complete" else { return [] }
        return sourceEvent.embeds.filter(\.hasReadableContent)
    }

    private func withoutMassMentions(in source: String) -> String {
        ["@everyone", "@here"].reduce(source) { body, mention in
            body.replacingOccurrences(of: mention, with: "")
        }
    }

    @MainActor var isToday: Bool { sourceDate.map(AppTime.calendar.isDateInToday) ?? false }

    @MainActor var outcomes: [(accountID: String, outcome: DestinationOutcome)] {
        destinations.map { ($0.accountID, DestinationOutcome($0)) }
    }
}

enum ActivitySourceText {
    static func hasReadableText(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The enclosing row or card owns navigation, including links in captured source text.
    static func formattedPreview(_ text: String) -> AttributedString {
        var attributed =
            (try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(text)
        for run in attributed.runs where run.link != nil {
            attributed[run.range].link = nil
        }
        return attributed
    }
}

extension SourceEmbedEvidence {
    var hasReadableContent: Bool {
        ActivitySourceText.hasReadableText(title)
            || ActivitySourceText.hasReadableText(description)
            || fields.contains {
                ActivitySourceText.hasReadableText($0.name)
                    || ActivitySourceText.hasReadableText($0.value)
            }
    }
}

extension SourceInstruction {
    /// "Buy ABC at $12.34", "Sell half of ABC at $14", "Sell all ABC at the market price".
    @MainActor
    var phrase: String {
        // A sell the guru gave no price sells at the market, priced from the live bid (ADR-0007).
        let price =
            price.map { Decimal(engine: $0).map { $0.formatted(.currency(code: "USD")) } ?? $0 }
            ?? L10n.string("the market price")
        switch action {
        case "buy":
            return L10n.string("Buy %@ at %@", symbol, price)
        case "close":
            return L10n.string("Sell all %@ at %@", symbol, price)
        default:
            let share = L10n.string(fraction.map(Self.share) ?? "some")
            return L10n.string("Sell %@ of %@ at %@", share, symbol, price)
        }
    }

    private static func share(_ fraction: String) -> String {
        switch Humanize.fraction(fraction) {
        case "1/2": "half"
        case "1/3": "a third"
        case "1/4": "a quarter"
        case "2/3": "two thirds"
        case "3/4": "three quarters"
        case "1": "all"
        case let other: other
        }
    }
}
