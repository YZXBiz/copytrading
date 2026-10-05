import Foundation

/// How the reader read a post (ADR-0007): the engine's `PostReading`, one shape for every guru.
/// Each choice is a tagged alternative, as in the engine, and every stated value carries the
/// post's own words beside it. Amounts stay the engine's decimal strings.
public enum PostReading: Codable, Equatable, Sendable {
    case tradeMade(summary: String, calls: [ReadCall])
    case instruction(summary: String, calls: [ReadCall])
    case conditional(summary: String, condition: String, calls: [ReadCall])
    case suggestion(summary: String, calls: [ReadCall])
    case commentary(summary: String)
    case unclear(summary: String)

    public var summary: String {
        switch self {
        case .tradeMade(let summary, _), .instruction(let summary, _), .conditional(let summary, _, _),
            .suggestion(let summary, _), .commentary(let summary), .unclear(let summary):
            summary
        }
    }

    public var calls: [ReadCall] {
        switch self {
        case .tradeMade(_, let calls), .instruction(_, let calls), .conditional(_, _, let calls),
            .suggestion(_, let calls):
            calls
        case .commentary, .unclear: []
        }
    }

    /// The post's words behind each value, in the order the reading states them.
    public var citedWords: [String] {
        var words: [String] = []
        if case .conditional(_, let condition, _) = self { words.append(condition) }
        for call in calls { words += call.citedWords }
        return words
    }

    private enum Key: String, CodingKey { case kind, summary, condition, calls }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let summary = try container.decode(String.self, forKey: .summary)
        switch try container.decode(String.self, forKey: .kind) {
        case "trade_made": self = .tradeMade(summary: summary, calls: try container.decode([ReadCall].self, forKey: .calls))
        case "instruction": self = .instruction(summary: summary, calls: try container.decode([ReadCall].self, forKey: .calls))
        case "conditional":
            self = .conditional(
                summary: summary, condition: try container.decode(String.self, forKey: .condition),
                calls: try container.decode([ReadCall].self, forKey: .calls))
        case "suggestion": self = .suggestion(summary: summary, calls: try container.decode([ReadCall].self, forKey: .calls))
        case "commentary": self = .commentary(summary: summary)
        case "unclear": self = .unclear(summary: summary)
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown reading \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(summary, forKey: .summary)
        switch self {
        case .tradeMade(_, let calls): try container.encode("trade_made", forKey: .kind); try container.encode(calls, forKey: .calls)
        case .instruction(_, let calls): try container.encode("instruction", forKey: .kind); try container.encode(calls, forKey: .calls)
        case .conditional(_, let condition, let calls):
            try container.encode("conditional", forKey: .kind)
            try container.encode(condition, forKey: .condition)
            try container.encode(calls, forKey: .calls)
        case .suggestion(_, let calls): try container.encode("suggestion", forKey: .kind); try container.encode(calls, forKey: .calls)
        case .commentary: try container.encode("commentary", forKey: .kind)
        case .unclear: try container.encode("unclear", forKey: .kind)
        }
    }
}

/// One call in a reading: a buy or a sell.
public enum ReadCall: Codable, Equatable, Sendable {
    case buy(ReadBuy)
    case sell(ReadSell)

    public var stock: ReadStock {
        switch self {
        case .buy(let buy): buy.stock
        case .sell(let sell): sell.stock
        }
    }

    public var price: ReadPrice {
        switch self {
        case .buy(let buy): buy.price
        case .sell(let sell): sell.price
        }
    }

    public var citedWords: [String] {
        switch self {
        case .buy(let buy): [buy.actionWords, buy.stock.words] + buy.price.words + buy.size.words
        case .sell(let sell): [sell.actionWords, sell.stock.words] + sell.price.words + sell.share.words + sell.sellFrom.words
        }
    }

    private enum Key: String, CodingKey { case action }

    public init(from decoder: any Decoder) throws {
        let action = try decoder.container(keyedBy: Key.self).decode(String.self, forKey: .action)
        self = action == "buy" ? .buy(try ReadBuy(from: decoder)) : .sell(try ReadSell(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .buy(let buy): try buy.encode(to: encoder)
        case .sell(let sell): try sell.encode(to: encoder)
        }
    }
}

public struct ReadStock: Codable, Equatable, Sendable {
    public let ticker: String
    public let words: String
}

public struct ReadBuy: Codable, Equatable, Sendable {
    public let actionWords: String
    public let stock: ReadStock
    public let price: ReadPrice
    public let size: ReadSize

    enum CodingKeys: String, CodingKey {
        case action
        case actionWords = "action_words"
        case stock, price, size
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actionWords = try container.decode(String.self, forKey: .actionWords)
        stock = try container.decode(ReadStock.self, forKey: .stock)
        price = try container.decode(ReadPrice.self, forKey: .price)
        size = try container.decode(ReadSize.self, forKey: .size)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("buy", forKey: .action)
        try container.encode(actionWords, forKey: .actionWords)
        try container.encode(stock, forKey: .stock)
        try container.encode(price, forKey: .price)
        try container.encode(size, forKey: .size)
    }
}

public struct ReadSell: Codable, Equatable, Sendable {
    public let actionWords: String
    public let stock: ReadStock
    public let price: ReadPrice
    public let share: ReadShare
    /// Whether a share counts from the original buy or what is left; nil when the post doesn't say.
    public let countsFrom: String?
    public let sellFrom: ReadSellFrom

    enum CodingKeys: String, CodingKey {
        case action
        case actionWords = "action_words"
        case stock, price, share
        case countsFrom = "counts_from"
        case sellFrom = "sell_from"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actionWords = try container.decode(String.self, forKey: .actionWords)
        stock = try container.decode(ReadStock.self, forKey: .stock)
        price = try container.decode(ReadPrice.self, forKey: .price)
        share = try container.decode(ReadShare.self, forKey: .share)
        countsFrom = try container.decodeIfPresent(String.self, forKey: .countsFrom)
        sellFrom = try container.decode(ReadSellFrom.self, forKey: .sellFrom)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("sell", forKey: .action)
        try container.encode(actionWords, forKey: .actionWords)
        try container.encode(stock, forKey: .stock)
        try container.encode(price, forKey: .price)
        try container.encode(share, forKey: .share)
        try container.encode(countsFrom, forKey: .countsFrom)
        try container.encode(sellFrom, forKey: .sellFrom)
    }
}

public enum ReadPrice: Codable, Equatable, Sendable {
    case exact(value: String, words: String)
    case range(low: String, high: String, lowWords: String, highWords: String)
    case atMarket(words: String)
    case notGiven

    public var words: [String] {
        switch self {
        case .exact(_, let words), .atMarket(let words): [words]
        case .range(_, _, let low, let high): [low, high]
        case .notGiven: []
        }
    }

    private enum Key: String, CodingKey {
        case kind, value, words, low, high
        case lowWords = "low_words"
        case highWords = "high_words"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "exact": self = .exact(value: try c.decode(String.self, forKey: .value), words: try c.decode(String.self, forKey: .words))
        case "range":
            self = .range(
                low: try c.decode(String.self, forKey: .low), high: try c.decode(String.self, forKey: .high),
                lowWords: try c.decode(String.self, forKey: .lowWords), highWords: try c.decode(String.self, forKey: .highWords))
        case "at_market": self = .atMarket(words: try c.decode(String.self, forKey: .words))
        default: self = .notGiven
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .exact(let value, let words):
            try c.encode("exact", forKey: .kind); try c.encode(value, forKey: .value); try c.encode(words, forKey: .words)
        case .range(let low, let high, let lowWords, let highWords):
            try c.encode("range", forKey: .kind)
            try c.encode(low, forKey: .low)
            try c.encode(high, forKey: .high)
            try c.encode(lowWords, forKey: .lowWords)
            try c.encode(highWords, forKey: .highWords)
        case .atMarket(let words): try c.encode("at_market", forKey: .kind); try c.encode(words, forKey: .words)
        case .notGiven: try c.encode("not_given", forKey: .kind)
        }
    }
}

public enum ReadSize: Codable, Equatable, Sendable {
    case fraction(value: String, words: String)
    case batch(number: Int, words: String)
    case notGiven

    public var words: [String] {
        switch self {
        case .fraction(_, let words), .batch(_, let words): [words]
        case .notGiven: []
        }
    }

    private enum Key: String, CodingKey { case kind, value, number, words }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "fraction":
            self = .fraction(value: try c.decode(String.self, forKey: .value), words: try c.decode(String.self, forKey: .words))
        case "batch": self = .batch(number: try c.decode(Int.self, forKey: .number), words: try c.decode(String.self, forKey: .words))
        default: self = .notGiven
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .fraction(let value, let words):
            try c.encode("fraction", forKey: .kind); try c.encode(value, forKey: .value); try c.encode(words, forKey: .words)
        case .batch(let number, let words):
            try c.encode("batch", forKey: .kind); try c.encode(number, forKey: .number); try c.encode(words, forKey: .words)
        case .notGiven: try c.encode("not_given", forKey: .kind)
        }
    }
}

public enum ReadShare: Codable, Equatable, Sendable {
    case fraction(value: String, words: String)
    case all(words: String)

    public var words: [String] {
        switch self {
        case .fraction(_, let words), .all(let words): [words]
        }
    }

    private enum Key: String, CodingKey { case kind, value, words }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let words = try c.decode(String.self, forKey: .words)
        self =
            try c.decode(String.self, forKey: .kind) == "fraction"
            ? .fraction(value: try c.decode(String.self, forKey: .value), words: words) : .all(words: words)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .fraction(let value, let words):
            try c.encode("fraction", forKey: .kind); try c.encode(value, forKey: .value); try c.encode(words, forKey: .words)
        case .all(let words): try c.encode("all", forKey: .kind); try c.encode(words, forKey: .words)
        }
    }
}

public enum ReadSellFrom: Codable, Equatable, Sendable {
    case lot(buyPrice: String, words: String)
    case notSaid

    public var words: [String] {
        if case .lot(_, let words) = self { return [words] }
        return []
    }

    private enum Key: String, CodingKey {
        case kind, words
        case buyPrice = "buy_price"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self =
            try c.decode(String.self, forKey: .kind) == "lot"
            ? .lot(buyPrice: try c.decode(String.self, forKey: .buyPrice), words: try c.decode(String.self, forKey: .words))
            : .notSaid
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .lot(let buyPrice, let words):
            try c.encode("lot", forKey: .kind); try c.encode(buyPrice, forKey: .buyPrice); try c.encode(words, forKey: .words)
        case .notSaid: try c.encode("not_said", forKey: .kind)
        }
    }
}
