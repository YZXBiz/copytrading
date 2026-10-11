import DesktopCore
import Foundation
import Testing

/// A post the reader couldn't read is filled in from its words for the owner to confirm, and the
/// choices build the same manual instruction the engine has always taken.
func runManualInstructionGuessTests() throws {
    try aSellOfHalfTheHeldStockIsReadFromItsWords()
    try aBuyKeepsTheGurusSizeAndPrice()
    try closingWordsSellEverything()
    try aPostWithNoTradeLeavesTheChoicesEmpty()
    try theChoicesBuildTheEnginesInstruction()
}

private func aSellOfHalfTheHeldStockIsReadFromItsWords() throws {
    let draft = try #require(ManualInstructionGuess.draft(from: "sell wmt half", held: ["PM", "WMT"]))
    try #require(draft.isSell && draft.symbol == "WMT" && draft.fraction == "0.5" && draft.postPrice.isEmpty)
    // No price in the post: the sell goes at the market, with no price on the wire.
    try #require(draft.sellsAtMarket && draft.value == ManualInstruction(action: .reduce, symbol: "WMT", price: nil, fraction: "0.5"))
    let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.value)) as? [String: Any]
    try #require(wire?["price"] is NSNull, "the engine requires the price key, null at the market")
    let trim = try #require(ManualInstructionGuess.draft(from: "trimming a third of $NVDA here 182.5", held: []))
    try #require(trim.isSell && trim.symbol == "NVDA" && ManualInstructionDraft.sameShare(trim.fraction, "0.3333333333"))
    try #require(trim.price == "182.5")
}

private func aBuyKeepsTheGurusSizeAndPrice() throws {
    let draft = try #require(ManualInstructionGuess.draft(from: "buy wmt 1/6 110", held: []))
    try #require(!draft.isSell && draft.symbol == "WMT" && draft.price == "110")
    try #require(ManualInstructionDraft.sameShare(draft.fraction, "\(Decimal(1) / Decimal(6))"))
    let some = try #require(ManualInstructionGuess.draft(from: "let's buy some nvda at the current price", held: []))
    try #require(!some.isSell && some.symbol == "NVDA" && some.price.isEmpty)
}

private func closingWordsSellEverything() throws {
    let draft = try #require(ManualInstructionGuess.draft(from: "Closing PM, out", held: ["PM"]))
    try #require(draft.isSell && draft.symbol == "PM" && draft.fraction == "1" && draft.action == .close)
}

private func aPostWithNoTradeLeavesTheChoicesEmpty() throws {
    try #require(ManualInstructionGuess.draft(from: "hi", held: ["WMT"]) == nil)
    try #require(ManualInstructionGuess.draft(from: "good morning everyone", held: []) == nil)
}

private func theChoicesBuildTheEnginesInstruction() throws {
    var sell = ManualInstructionDraft()
    sell.isSell = true
    sell.symbol = "wmt"
    sell.price = "110.06"
    sell.fraction = "0.5"
    try #require(sell.isValid)
    try #require(sell.value == ManualInstruction(action: .reduce, symbol: "WMT", price: "110.06", fraction: "0.5"))
    sell.fraction = "1"
    sell.entryPrice = "110"
    try #require(
        sell.value == ManualInstruction(action: .close, symbol: "WMT", price: "110.06", entryPrice: "110", fraction: "1"))

    let call = try JSONDecoder().decode(
        SourceInstruction.self, from: Data(#"{"action":"buy","symbol":"WMT","price":"110","fraction":"0.25"}"#.utf8))
    let buy = ManualInstructionDraft(call: call)
    try #require(buy.value == ManualInstruction(action: .buy, symbol: "WMT", price: "110", fraction: "0.25"))
    var priceless = buy
    priceless.price = ""
    try #require(!priceless.isValid, "an order needs a price above zero")
}
