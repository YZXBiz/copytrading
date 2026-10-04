import DesktopCore
import SwiftUI

struct ExampleReviewSection: View {
    let model: AppModel

    var body: some View {
        Section {
            ForEach(model.profileExampleReviews.keys.sorted(), id: \.self) { routeID in
                if let review = model.profileExampleReviews[routeID] {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(guruName(review.guruID))
                                .bold()
                            Text(L10n.string("Read by %@", review.model))
                                .font(.callout)
                                .foregroundStyle(.secondary)
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            if model.canAcknowledgeProfileExamples {
                if model.profileExamplesAcknowledged {
                    Label(L10n.string("You looked over these readings"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(L10n.string("These Readings Look Right"), systemImage: "checkmark", action: model.acknowledgeProfileExamples)
                        .accessibilityHint(L10n.string("Confirms the examples were read the way you meant. It cannot override a mismatch."))
                }
            }
        } header: {
            Label(L10n.string("How the examples were read"), systemImage: "text.magnifyingglass")
        }
    }

    private func guruName(_ guruID: String) -> String {
        let name = model.setupDraft.routes.first { $0.guruID.trimmed == guruID }?.displayName.trimmed ?? ""
        return name.isEmpty ? guruID : name
    }
}
