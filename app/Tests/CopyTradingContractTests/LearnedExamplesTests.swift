import DesktopCore
import Foundation
import Testing

/// Learn from Channel adds example posts beside the owner's own and never replaces them.
@MainActor
func runLearnedExamplesTests() throws {
    try learningKeepsTheOwnersExamples()
    try aLearnedPostThatIsAlreadyAnExampleIsSkipped()
    try learningWithNoExamplesChangesNothing()
    try examplesNeverPassTheEnginesLimit()
}

private func example(_ message: String, _ symbol: String = "SOUN") -> TradingProfileExample {
    TradingProfileExample(message: message, expectedAction: .buy, expectedSymbol: symbol, expectedFraction: "0.5")
}

private func routeWithOwnersExample() -> TradingRouteDraft {
    TradingRouteDraft(
        displayName: "Zhao",
        examples: [TradingProfileExampleDraft(message: "5.85加了6分之一soun", expectedSymbol: "SOUN")])
}

private func learningKeepsTheOwnersExamples() throws {
    var route = routeWithOwnersExample()
    let added = route.addLearnedExamples([example("25加了一半abc", "ABC")])
    try #require(added == 1, "the learned example was not counted")
    try #require(
        route.examples.map(\.message) == ["5.85加了6分之一soun", "25加了一半abc"],
        "learning replaced or reordered the owner's example")
}

private func aLearnedPostThatIsAlreadyAnExampleIsSkipped() throws {
    var route = routeWithOwnersExample()
    let added = route.addLearnedExamples([example(" 5.85加了6分之一soun\n"), example("25加了一半abc"), example("25加了一半abc")])
    try #require(added == 1, "a post that is already an example, or repeats, was added again")
    try #require(route.examples.count == 2, "learning duplicated an example")
    try #require(route.examples[0].expectedSymbol == "SOUN", "the owner's version of a post was overwritten")
}

private func learningWithNoExamplesChangesNothing() throws {
    var route = routeWithOwnersExample()
    try #require(route.addLearnedExamples([]) == 0, "nothing learned still counted as added")
    try #require(route.examples.count == 1, "learning without examples wiped the owner's example")
}

private func examplesNeverPassTheEnginesLimit() throws {
    var route = routeWithOwnersExample()
    let learned = (1...40).map { example("\($0)加了一半abc", "ABC") }
    let added = route.addLearnedExamples(learned)
    try #require(route.examples.count == TradingRouteDraft.maximumExamples, "examples passed the engine's limit")
    try #require(added == TradingRouteDraft.maximumExamples - 1, "the added count is wrong at the limit")
}
