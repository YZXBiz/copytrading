import Foundation

/// The likeliest trade in a post the reader couldn't read, from its words alone, so the owner only
/// has to confirm it: "sell wmt half" is a sell of half the WMT held. Nothing here reaches the
/// engine until the owner sends it.
enum ManualInstructionGuess {
    private static let sellWords: Set<String> = [
        "sell", "sold", "selling", "trim", "trimmed", "trimming", "close", "closed",
        "closing", "cut", "exit", "exited", "dump", "out", "tp",
    ]
    /// Words that by themselves mean selling everything.
    private static let sellAllWords: Set<String> = ["close", "closed", "closing", "exit", "exited", "dump", "out"]
    private static let buyWords: Set<String> = [
        "buy", "bought", "buying", "add", "added", "adding", "long", "enter",
        "entered", "starter", "open", "opened",
    ]
    /// Short words that look like tickers in a post written in capitals.
    private static let notTickers: Set<String> = [
        "I", "A", "AT", "THE", "AND", "OR", "TO", "OF", "IN", "ON", "FOR", "IS",
        "IT", "MY", "ALL", "HALF", "BUY", "SELL", "TP", "PT", "SL", "OUT", "ADD", "CUT", "NOW", "USD", "ETF", "AM", "PM",
        "EOD", "LOL", "IMO", "ATH", "GO", "UP", "NO", "SO", "BE", "WE", "ME", "AN", "AS", "BY", "IF", "OK", "SOME", "MORE",
        "BACK", "THIS", "THAT", "HERE", "MOST", "FEW", "AGAIN", "SHARE", "BIT",
    ]

    /// A buy or a sell guessed from `text`, with the stock matched first against `held`, or nil when
    /// the post names neither a direction nor a stock.
    static func draft(from text: String, held: [String]) -> ManualInstructionDraft? {
        let lowered = text.lowercased()
        let words = words(in: lowered)
        let sells = words.contains(where: sellWords.contains) || lowered.contains("take profit")
        let buys = words.contains(where: buyWords.contains)
        let symbol = symbol(in: text, held: held)
        guard sells || buys || symbol != nil else { return nil }
        var draft = ManualInstructionDraft()
        // A post that both buys and sells reads as a sell when the stock is already held.
        draft.isSell = sells && (!buys || symbol.map { held.contains($0) } == true)
        draft.symbol = symbol ?? ""
        let price = price(in: text)
        draft.postPrice = price.map { "\($0)" } ?? ""
        draft.price = draft.postPrice
        if let share = share(in: lowered) {
            draft.fraction = share
        } else if draft.isSell, words.contains(where: sellAllWords.contains) {
            draft.fraction = "1"
        }
        if !draft.isSell, draft.fraction == "1" { draft.fraction = "" }
        return draft
    }

    /// The share a post names: "half", "a third", "1/4", "25%", "all".
    static func share(in lowered: String) -> String? {
        let words = words(in: lowered)
        let joined = " " + words.joined(separator: " ") + " "
        let named: [(String, String)] = [
            (" three quarters ", "0.75"), (" 3/4 ", "0.75"), (" 75% ", "0.75"),
            (" two thirds ", "\(Decimal(2) / Decimal(3))"), (" 2/3 ", "\(Decimal(2) / Decimal(3))"),
            (" half ", "0.5"), (" 1/2 ", "0.5"), (" 50% ", "0.5"),
            (" third ", "\(Decimal(1) / Decimal(3))"), (" 1/3 ", "\(Decimal(1) / Decimal(3))"),
            (" quarter ", "0.25"), (" 1/4 ", "0.25"), (" 25% ", "0.25"),
            (" sixth ", "\(Decimal(1) / Decimal(6))"), (" 1/6 ", "\(Decimal(1) / Decimal(6))"),
            (" all ", "1"), (" everything ", "1"), (" rest ", "1"), (" full ", "1"),
        ]
        return named.first { joined.contains($0.0) }?.1
    }

    /// The first plain number in a post that isn't a share: "wmt 1/6 110" → 110.
    static func price(in text: String) -> Decimal? {
        for word in words(in: text.lowercased()) where !word.contains("/") && !word.hasSuffix("%") {
            let digits = word.trimmingCharacters(in: CharacterSet(charactersIn: "$@"))
            guard digits.first?.isNumber == true, let value = Decimal(string: digits), value > 0, value <= 100_000 else {
                continue
            }
            return value
        }
        return nil
    }

    /// A held stock the post names in any case, else a `$TICKER` or a word in capitals.
    static func symbol(in text: String, held: [String]) -> String? {
        let raw = text.split(whereSeparator: { $0.isWhitespace || ",.!?;:()\"“”'".contains($0) }).map(String.init)
        let bare = raw.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "$#")).uppercased() }
        if let match = bare.first(where: { held.contains($0) }) { return match }
        if let cashtag = raw.first(where: { $0.hasPrefix("$") && $0.dropFirst().allSatisfy(\.isLetter) && $0.count > 1 }) {
            return cashtag.dropFirst().uppercased()
        }
        if let capitals = raw.first(where: { word in
            (1...5).contains(word.count) && word.allSatisfy { $0.isUppercase && $0.isLetter } && !notTickers.contains(word)
        }) {
            return capitals
        }
        // A post in lower case: the first short word after "sell" or "buy" that isn't a filler
        // ("buy some nvda").
        let lowered = raw.map { $0.lowercased() }
        for (index, word) in lowered.enumerated() where sellWords.contains(word) || buyWords.contains(word) {
            for next in bare.dropFirst(index + 1).prefix(3) {
                if notTickers.contains(next) || share(in: next.lowercased()) != nil { continue }
                if (1...5).contains(next.count), next.allSatisfy(\.isLetter) { return next }
                break
            }
        }
        return nil
    }

    private static func words(in lowered: String) -> [String] {
        lowered.split(whereSeparator: { $0.isWhitespace || ",!?;:()\"“”".contains($0) }).map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
    }
}
