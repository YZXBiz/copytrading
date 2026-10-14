import DesktopCore
import Foundation
import Testing

private func readings() throws -> [PostReading] {
    try JSONDecoder().decode([PostReading].self, from: contractFixture("post-readings.json"))
}

@Test func everyReadingTheEngineWritesDecodesAndEncodesBack() throws {
    let decoded = try readings()

    #expect(decoded.count == 12)
    let reencoded = try JSONDecoder().decode([PostReading].self, from: JSONEncoder().encode(decoded))
    #expect(reencoded == decoded)
}

@Test func aReadingNamesTheWordsItTookEachValueFrom() throws {
    let suggestion = try readings()[3]

    guard case .suggestion = suggestion else { Issue.record("expected a suggestion"); return }
    #expect(suggestion.citedWords == ["建仓", "Cbrs", "160", "179"])
}

@Test func aConditionsWordsAreCitedFirst() throws {
    let conditional = try readings()[4]

    #expect(conditional.citedWords.first == "如果明天20以下")
    #expect(conditional.calls.count == 1)
}

@Test func chatterCarriesNoWordsAndEncodesBackAsIs() throws {
    let chatter = try readings()[8]

    #expect(chatter == .chatter && chatter.calls.isEmpty && chatter.citedWords.isEmpty)
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(chatter)) as? [String: String]
    #expect(encoded == ["kind": "chatter"])
}

@Test func aVagueTrimStatesNoShareAndStillDecodes() throws {
    let trim = try readings()[11]

    guard case .sell(let sell) = try #require(trim.calls.first) else { Issue.record("expected a sell"); return }
    #expect(sell.share == .notGiven && sell.share.words.isEmpty)
    #expect(trim.citedWords == ["trim", "KO", "trim"])
}
