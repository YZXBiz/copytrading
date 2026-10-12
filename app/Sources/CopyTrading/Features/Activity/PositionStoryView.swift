import SwiftUI

/// A holding told start to finish in a post's account result: each buy and sale on one ink rail,
/// the step this post made marked in butter, and what it came to once it was all sold.
struct PositionStoryView: View {
    let story: PositionStory
    let directory: GuruDirectory
    /// The words of a post Activity still holds, for the steps other posts made.
    let postText: (String) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("%@, start to finish", story.symbol))
                .font(DisplayFont.font(size: 24, weight: .medium, relativeTo: .title2))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 22)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(story.steps.enumerated()), id: \.offset) { index, step in
                stepRow(step, isLast: index == story.steps.count - 1)
            }
            if let result = story.result {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.string("Result"))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.tertiaryInk)
                    Spacer()
                    MoneyText(
                        value: result, style: .change,
                        font: DisplayFont.font(size: 20, weight: .medium, relativeTo: .title3))
                }
                .padding(.top, 20)
                .padding(.leading, 25)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepRow(_ step: PositionStory.Step, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(step.kind == .sold || step.kind == .soldAll ? Palette.sky : Palette.sage)
                    .overlay(Circle().stroke(Palette.ink, lineWidth: 1.4))
                    .frame(width: 11, height: 11)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(Palette.ink.opacity(0.35))
                        .frame(width: 1.4)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 11)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(headline(step))
                        .font(DesignTokens.bodyText.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .markerHighlight(step.isThisPost)
                    Spacer(minLength: 8)
                    MoneyText(value: step.amount, font: DisplayFont.font(size: 20, weight: .medium, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                }
                Text(detail(step))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Bought 6.973 shares at $70.80", "You sold all 8.329 shares at $70.79".
    private func headline(_ step: PositionStory.Step) -> String {
        let shares = shareCount(step.shares)
        let price = step.price.formatted(.currency(code: "USD"))
        switch (step.kind, step.byOwner) {
        case (.bought, _): return L10n.string("Bought %@ at %@", shares, price)
        case (.added, _): return L10n.string("Added %@ at %@", shares, price)
        case (.sold, true): return L10n.string("You sold %@ at %@", shares, price)
        case (.sold, false): return L10n.string("Sold %@ at %@", shares, price)
        case (.soldAll, true): return L10n.string("You sold all %@ at %@", shares, price)
        case (.soldAll, false): return L10n.string("Sold all %@ at %@", shares, price)
        }
    }

    /// Who made the step and when: this post, another post and its words, or the owner.
    private func detail(_ step: PositionStory.Step) -> String {
        let time = step.at.formatted(AppTime.style(.dateTime.hour().minute()))
        if step.isThisPost { return L10n.string("This post · %@", time) }
        if step.byOwner { return L10n.string("You, from the account page · %@", time) }
        let who = directory.name(for: step.guruID) ?? L10n.string("Copied post")
        if let messageID = step.messageID, let text = postText(messageID) {
            return L10n.string("%@ · %@ · “%@”", who, time, text)
        }
        return L10n.string("%@ · %@", who, time)
    }

    /// Shares to the thousandth, as the story reads them: "6.973 shares".
    private func shareCount(_ value: Decimal) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...3)))
        return value == 1 ? L10n.string("%@ share", number) : L10n.string("%@ shares", number)
    }
}
