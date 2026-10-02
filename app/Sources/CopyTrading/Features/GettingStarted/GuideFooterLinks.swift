import SwiftUI

/// Where to ask for help, and the button that brings the tips back.
struct GuideFooterLinks: View {
    let model: AppModel

    var body: some View {
        Text(L10n.string("Questions, ideas, or a bug?"))
            .font(DesignTokens.bodyText)
            .foregroundStyle(Palette.secondaryInk)
        Link(destination: HelpLinks.reportProblem) {
            Label(L10n.string("Report a Problem"), systemImage: "arrow.up.forward.square")
        }
        .font(DesignTokens.bodyText)
        Spacer(minLength: 12)
        Button(L10n.string("Show Tips Again"), systemImage: "lightbulb", action: model.showTipsAgain)
            .buttonStyle(.borderless)
            .font(DesignTokens.bodyText)
            .help(L10n.string("Tips point out things like measuring on the chart; each shows once"))
            .accessibilityIdentifier("guide.showTipsAgain")
    }
}
