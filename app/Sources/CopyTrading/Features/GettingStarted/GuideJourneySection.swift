import DesktopCore
import SwiftUI

/// How a post becomes a trade: one guru post followed through six stages, each with what the
/// owner controls and the one thing to keep in mind.
struct GuideJourneySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GuideJourneyStage(
                number: 1, title: "A guru posts",
                text: "Every post in the channels you add, the moment it arrives.",
                control: "Which channels and gurus, in **Connections**.",
                caution: "Your Mac must be awake, with CopyTrading open.",
                figureDescription: "A guru's post: added a sixth of a position in SOUN at 5.85."
            ) {
                GuidePostSlip(name: "Alex Chen", time: "9:41", text: "Added 1/6 position SOUN at 5.85")
            }
            Divider()
            GuideJourneyStage(
                number: 2, title: "The AI reads it",
                text: "Into exact calls, from the post's own words. It needs **the stock** and **the price**; the size is optional.",
                control: "Each guru's playbook, drafted by **Learn**.",
                caution: "An \"if\", a range or no price **waits for you**.",
                figureDescription: "Read as a trade the guru made: buy SOUN at $5.85, a sixth of a full position."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("Read as · %@", L10n.string("a trade the guru made")))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                    Text(L10n.string("Buy SOUN at $5.85, a sixth of a full position."))
                        .font(DesignTokens.cardSerif)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            GuideJourneyStage(
                number: 3, title: "Your limits check it",
                text: "The guru's share of your **max per stock**, made smaller or skipped by your other limits.",
                control: "Every limit, per account, in **Connections**.",
                caution: "New accounts start with **entries off**.",
                figureDescription: "Two limits: $1,500 of $2,000 per stock, and $40 of a $250 daily loss cap."
            ) {
                VStack(spacing: 12) {
                    LimitMeter(title: "Max per stock", used: 1500, limit: 2000)
                    LimitMeter(title: "Daily loss cap", used: 40, limit: 250)
                }
            }
            Divider()
            GuideJourneyStage(
                number: 4, title: "The order goes to Alpaca",
                text: "A limit order, never above the guru's price plus your allowance.",
                control: "**Maximum above signal price** and **Order timeout**.",
                caution: "Unfilled by the order timeout, it's cancelled.",
                figureDescription: "The paper account primary filled 42 SOUN at $5.85."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(verbatim: "primary").font(DesignTokens.bodyEmphasis).foregroundStyle(Palette.ink)
                        EnvironmentBadge(environment: .paper)
                    }
                    StatusBadge(L10n.string("Filled"), tone: .positive)
                    Text(L10n.string("%@ %@ at %@", "42", "SOUN", "$5.85"))
                        .font(DesignTokens.bodyText)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            GuideJourneyStage(
                number: 5, title: "You see what happened",
                text: "Every post ends with an outcome and the reason, in **Activity**.",
                control: "Copy or skip a waiting call until its day ends.",
                caution: "Each account decides on its own.",
                figureDescription: "Three outcomes: traded smaller, waiting for you, and skipped."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(L10n.string("Traded smaller"), tone: .neutral)
                    StatusBadge(L10n.string("Waiting for you"), tone: .caution)
                    StatusBadge(L10n.string("Skipped"), tone: .inactive)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            GuideJourneyStage(
                number: 6, title: "When the guru sells",
                text:
                    "That part of what it bought on the guru's calls, at no less than their price less your allowance, 1% unless you change it.",
                control: "**Copy exits**, and selling any lot yourself in **Accounts**.",
                caution: "Never your own shares, and no stop-loss of its own.",
                figureDescription: "A guru's post: sold half of the SOUN bought at 5.85, at 6.40."
            ) {
                GuidePostSlip(name: "Alex Chen", time: "14:02", text: "Sold half of my 5.85 SOUN at 6.40")
            }
        }
    }
}
