import SwiftUI

/// How a post becomes a trade: the journey drawn as one path, then each of its six stages in a
/// few words, with what the owner controls and the one thing to keep in mind.
struct GuideJourneySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            GuideJourneyDiagram()
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 32, alignment: .top), GridItem(.flexible(), alignment: .top)],
                alignment: .leading, spacing: 26
            ) {
                GuideJourneyStage(
                    number: 1, title: "A guru posts",
                    text: "Every post in the channels you add, the moment it arrives.",
                    control: "Which channels and gurus, in **Connections**.",
                    caution: "Your Mac must be awake, with CopyTrading open.")
                GuideJourneyStage(
                    number: 2, title: "The AI reads it",
                    text: "Into exact calls, from the post's own words. It needs **the stock** and **the price**; the size is optional.",
                    control: "Each guru's playbook, drafted by **Learn**.",
                    caution: "An \"if\", a range or no price **waits for you**.")
                GuideJourneyStage(
                    number: 3, title: "Your limits check it",
                    text: "The guru's share of your **max per stock**, made smaller or skipped by your other limits.",
                    control: "Every limit, per account, in **Connections**.",
                    caution: "New accounts start with **entries off**.")
                GuideJourneyStage(
                    number: 4, title: "The order goes to Alpaca",
                    text: "A limit order, never above the guru's price plus your allowance.",
                    control: "**Maximum above signal price** and **Order timeout**.",
                    caution: "Unfilled by the order timeout, it's cancelled.")
                GuideJourneyStage(
                    number: 5, title: "You see what happened",
                    text: "Every post ends with an outcome and the reason, in **Activity**.",
                    control: "Copy or skip a waiting call until its day ends.",
                    caution: "Each account decides on its own.")
                GuideJourneyStage(
                    number: 6, title: "When the guru sells",
                    text:
                        "That part of what it bought on the guru's calls, at no less than their price less your allowance, 1% unless you change it.",
                    control: "**Copy exits**, and selling any lot yourself in **Accounts**.",
                    caution: "Never your own shares, and no stop-loss of its own.")
            }
        }
    }
}
