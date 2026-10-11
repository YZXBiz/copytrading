import DesktopCore
import SwiftUI

struct ExampleReviewSection: View {
    let model: AppModel

    var body: some View {
        SheetSection(L10n.string("How the examples were read")) {
            ForEach(model.profileExampleReviews.keys.sorted(), id: \.self) { routeID in
                if let review = model.profileExampleReviews[routeID] {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(guruName(review.guruID))
                                .font(DesignTokens.rowTitle)
                                .foregroundStyle(Palette.ink)
                            Text(L10n.string("Read by %@", review.model))
                                .font(DesignTokens.caption)
                                .foregroundStyle(Palette.tertiaryInk)
                        }
                        ForEach(review.examples, id: \.exampleIndex) { example in
                            ExampleComparisonRow(example: example)
                        }
                        if !review.automaticActivationAllowed {
                            Callout(
                                L10n.string(
                                    "An example was read differently from what you expected. Fix the playbook or the example in Connections, then start again."
                                ),
                                tone: .caution)
                        }
                        Text(L10n.string(review.costNotice))
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                    .padding(.vertical, 12)
                }
            }
            if model.canAcknowledgeProfileExamples {
                Text(L10n.string("Start Copying says these readings are what you meant."))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
    }

    private func guruName(_ guruID: String) -> String {
        let name = model.setupDraft.routes.first { $0.guruID.trimmed == guruID }?.displayName.trimmed ?? ""
        return name.isEmpty ? guruID : name
    }
}
