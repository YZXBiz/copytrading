import DesktopCore
import Foundation
import Testing

private func readings() throws -> [PostReading] {
    try JSONDecoder().decode([PostReading].self, from: contractFixture("post-readings.json"))
}

@Test func everyReadingTheEngineWritesDecodesAndEncodesBack() throws {
    let decoded = try readings()

    #expect(decoded.count == 9)
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
